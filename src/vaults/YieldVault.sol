// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IFXPool.sol";
import "../interfaces/IOraklFeed.sol";
import "../interfaces/IYieldStrategy.sol";
import "../interfaces/IYieldDistributor.sol";

/**
 * @title YieldVault
 *  @notice ERC-4626 vault that replaces FXPool for yield-enabled currency pools.
 *
 *          Architecture
 *          ────────────
 *          ┌──────────────────────────────────────────────┐
 *          │                 YieldVault                    │
 *          │  ERC-4626 share token  ·  IFXPool compatible  │
 *          │                                              │
 *          │  liquidReserve ──┐                           │
 *          │                  ├── totalAssets()            │
 *          │  strategy.val ───┘                           │
 *          │                                              │
 *          │  coverageRatio = liquid / totalAssets         │
 *          └───────────────┬──────────────────────────────┘
 *                          │
 *                    IYieldStrategy
 *                   (Aave / Pendle / …)
 *
 *          The vault holds a single stablecoin, priced via an Orakl USD feed.
 *          Idle capital above the target coverage ratio is deployed into an
 *          IYieldStrategy, and recalled automatically when needed for
 *          withdrawals or FXEngine releases.
 *
 *          The vault IS the LP/share token (standard ERC-4626 shares),
 *          so any DeFi aggregator can compose with it out of the box.
 *
 *          Security mitigations:
 *          - Dead shares on first deposit prevent ERC-4626 inflation attacks
 *          - All public entry points are nonReentrant + whenNotPaused
 *          - Two-step engine setter prevents instant fund-drain via malicious engine
 *          - Oracle staleness check prevents stale-price arbitrage
 */
contract YieldVault is ERC4626, IFXPool, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ── Constants ────────────────────────────────────────────────────────────
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_RATE = 1_000; // 10 %
    uint256 public constant RATIO_PRECISION = 10_000; // bps

    /// @notice Dead shares locked on first deposit to prevent inflation/donation attacks.
    uint256 public constant MINIMUM_SHARES = 1_000;

    // ── Immutables ───────────────────────────────────────────────────────────
    IOraklFeed private immutable _priceFeed;
    uint8 private immutable _feedDecimals;

    // ── Mutable state ────────────────────────────────────────────────────────
    address public fxEngine;
    address public pendingFxEngine;
    uint256 public override feeRate;

    /// @notice Max allowed age (seconds) for oracle data.
    uint256 public maxStaleness = 3600;

    IYieldStrategy public strategy;
    uint256 public targetCoverageRatio;

    /// @notice YieldDistributor that receives a share of harvested yield.
    address public distributor;
    /// @notice Percentage of harvest yield sent to the distributor (bps).
    uint256 public harvestFeeRate;

    /// @notice Tracks whether the first deposit (dead shares) has been done.
    bool private _initialized;

    // ── Events ───────────────────────────────────────────────────────────────
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event Rebalanced(uint256 deposited, uint256 withdrawn);
    event YieldHarvested(uint256 profit);
    event CoverageRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event HarvestFeeCollected(uint256 fee);
    event DistributorUpdated(address indexed oldDist, address indexed newDist);
    event HarvestFeeRateUpdated(uint256 oldRate, uint256 newRate);

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(
        IERC20 asset_,
        address priceFeed_,
        string memory name_,
        string memory symbol_,
        uint256 feeRate_,
        uint256 targetCoverageRatio_,
        address owner_
    ) ERC20(name_, symbol_) ERC4626(asset_) Ownable(owner_) {
        require(priceFeed_ != address(0), "YieldVault: zero priceFeed");
        require(feeRate_ <= MAX_FEE_RATE, "YieldVault: fee too high");
        require(targetCoverageRatio_ <= RATIO_PRECISION, "YieldVault: invalid ratio");

        _priceFeed = IOraklFeed(priceFeed_);
        _feedDecimals = IOraklFeed(priceFeed_).decimals();
        feeRate = feeRate_;
        targetCoverageRatio = targetCoverageRatio_;
    }

    // =====================================================================
    //  ERC-4626 overrides
    // =====================================================================

    /// @dev Total assets = liquid balance held here + value deployed in strategy.
    function totalAssets() public view override returns (uint256) {
        uint256 liquid = IERC20(asset()).balanceOf(address(this));
        uint256 deployed = address(strategy) != address(0) ? strategy.totalValue() : 0;
        return liquid + deployed;
    }

    /// @dev Lock dead shares on the very first deposit to prevent inflation attacks.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        if (!_initialized) {
            _initialized = true;
            require(shares > MINIMUM_SHARES, "YieldVault: initial deposit too small");
            _transfer(receiver, address(0xdead), MINIMUM_SHARES);
        }
    }

    /// @dev On withdraw / redeem, recall from strategy when liquid reserve is short.
    function _withdraw(address caller, address receiver, address tokenOwner, uint256 assets, uint256 shares)
        internal
        override
    {
        _ensureLiquidity(assets);
        super._withdraw(caller, receiver, tokenOwner, assets, shares);
    }

    // ── ERC-4626 public entry points: nonReentrant + whenNotPaused ──────────

    function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    // =====================================================================
    //  IFXPool compatibility  (so FXEngine can use YieldVaults as pools)
    // =====================================================================

    /// @inheritdoc IFXPool
    function deposit(uint256 amount) external override(IFXPool) returns (uint256 lpMinted) {
        uint256 balBefore = balanceOf(msg.sender);
        deposit(amount, msg.sender);
        lpMinted = balanceOf(msg.sender) - balBefore;
        emit Deposited(msg.sender, amount, lpMinted);
    }

    /// @inheritdoc IFXPool
    function withdraw(uint256 lpAmount) external override(IFXPool) returns (uint256 amount) {
        amount = redeem(lpAmount, msg.sender, msg.sender);
        emit Withdrawn(msg.sender, lpAmount, amount);
    }

    /// @inheritdoc IFXPool
    function release(uint256 amount, address to) external override nonReentrant whenNotPaused {
        require(msg.sender == fxEngine, "YieldVault: only engine");
        require(to != address(0), "YieldVault: zero recipient");

        _ensureLiquidity(amount);

        require(IERC20(asset()).balanceOf(address(this)) >= amount, "YieldVault: insufficient liquidity after recall");
        IERC20(asset()).safeTransfer(to, amount);

        emit Released(amount, to);
    }

    /// @inheritdoc IFXPool
    function getPrice() external view override returns (int256 price, uint8 decimals_) {
        uint256 updatedAt;
        (, price, updatedAt) = _priceFeed.latestRoundData();
        require(price > 0, "YieldVault: invalid price");
        require(block.timestamp - updatedAt <= maxStaleness, "YieldVault: stale price");
        decimals_ = _feedDecimals;
    }

    /// @notice Returns **total** managed balance (liquid + deployed) so FXEngine
    ///         can correctly check output liquidity before a swap.
    function getPoolBalance() external view override returns (uint256) {
        return totalAssets();
    }

    /// @notice The vault itself IS the LP / share token.
    function lpToken() external view override returns (address) {
        return address(this);
    }

    /// @notice The underlying stablecoin.
    function stablecoin() external view override returns (address) {
        return asset();
    }

    // =====================================================================
    //  Strategy management
    // =====================================================================

    /// @notice Replace the active yield strategy.
    ///         If an old strategy has deployed capital, it is fully recalled first.
    function setStrategy(address strategy_) external onlyOwner {
        if (address(strategy) != address(0)) {
            uint256 deployed = strategy.totalValue();
            if (deployed > 0) {
                strategy.withdraw(deployed);
            }
            IERC20(asset()).forceApprove(address(strategy), 0);
        }

        emit StrategyUpdated(address(strategy), strategy_);
        strategy = IYieldStrategy(strategy_);

        if (strategy_ != address(0)) {
            IERC20(asset()).forceApprove(strategy_, type(uint256).max);
        }
    }

    /// @notice Push / pull assets between liquid reserve and strategy to hit
    ///         the target coverage ratio.
    function rebalance() external onlyOwner {
        require(address(strategy) != address(0), "YieldVault: no strategy");

        uint256 total = totalAssets();
        if (total == 0) return;

        uint256 targetLiquid = (total * targetCoverageRatio) / RATIO_PRECISION;
        uint256 liquid = IERC20(asset()).balanceOf(address(this));

        if (liquid > targetLiquid) {
            uint256 excess = liquid - targetLiquid;
            strategy.deposit(excess);
            emit Rebalanced(excess, 0);
        } else if (liquid < targetLiquid) {
            uint256 deficit = targetLiquid - liquid;
            uint256 stratValue = strategy.totalValue();
            uint256 toRecall = deficit > stratValue ? stratValue : deficit;
            if (toRecall > 0) {
                strategy.withdraw(toRecall);
                emit Rebalanced(0, toRecall);
            }
        }
    }

    /// @notice Harvest accrued yield from the strategy.
    ///         Harvested tokens flow into the vault's liquid reserve, increasing
    ///         the value of every outstanding share.
    function harvest() external onlyOwner returns (uint256 profit) {
        require(address(strategy) != address(0), "YieldVault: no strategy");
        profit = strategy.harvest();

        if (profit > 0 && distributor != address(0) && harvestFeeRate > 0) {
            uint256 fee = (profit * harvestFeeRate) / FEE_DENOMINATOR;
            if (fee > 0) {
                IERC20(asset()).safeTransfer(distributor, fee);
                IYieldDistributor(distributor).notifyFees(address(this), fee);
                profit -= fee;
                emit HarvestFeeCollected(fee);
            }
        }

        emit YieldHarvested(profit);
    }

    // =====================================================================
    //  Coverage-ratio views
    // =====================================================================

    /// @notice Current liquid-to-total ratio in bps.
    function currentCoverageRatio() external view returns (uint256) {
        uint256 total = totalAssets();
        if (total == 0) return RATIO_PRECISION;
        return (IERC20(asset()).balanceOf(address(this)) * RATIO_PRECISION) / total;
    }

    /// @notice Stablecoin balance held directly in the vault (not deployed).
    function liquidReserve() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Capital currently deployed into the yield strategy.
    function deployedCapital() external view returns (uint256) {
        return address(strategy) != address(0) ? strategy.totalValue() : 0;
    }

    // =====================================================================
    //  Admin setters
    // =====================================================================

    /// @notice Propose a new FX engine. Must be accepted via acceptEngine().
    function proposeEngine(address engine_) external onlyOwner {
        require(engine_ != address(0), "YieldVault: zero engine");
        pendingFxEngine = engine_;
        emit EngineProposed(engine_);
    }

    /// @notice Accept a previously proposed engine, activating it.
    function acceptEngine() external onlyOwner {
        address pending = pendingFxEngine;
        require(pending != address(0), "YieldVault: no pending engine");
        emit EngineUpdated(fxEngine, pending);
        fxEngine = pending;
        pendingFxEngine = address(0);
    }

    function setFeeRate(uint256 feeRate_) external onlyOwner {
        require(feeRate_ <= MAX_FEE_RATE, "YieldVault: fee too high");
        emit FeeRateUpdated(feeRate, feeRate_);
        feeRate = feeRate_;
    }

    function setTargetCoverageRatio(uint256 ratio_) external onlyOwner {
        require(ratio_ <= RATIO_PRECISION, "YieldVault: invalid ratio");
        emit CoverageRatioUpdated(targetCoverageRatio, ratio_);
        targetCoverageRatio = ratio_;
    }

    function setDistributor(address dist_) external onlyOwner {
        emit DistributorUpdated(distributor, dist_);
        distributor = dist_;
    }

    function setHarvestFeeRate(uint256 rate_) external onlyOwner {
        require(rate_ <= 2_000, "YieldVault: harvest fee too high");
        emit HarvestFeeRateUpdated(harvestFeeRate, rate_);
        harvestFeeRate = rate_;
    }

    function setMaxStaleness(uint256 staleness_) external onlyOwner {
        require(staleness_ >= 60, "YieldVault: staleness too short");
        maxStaleness = staleness_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =====================================================================
    //  Internal helpers
    // =====================================================================

    /// @dev Recall from strategy if liquid reserve is below `needed`.
    ///      Reverts if the recall doesn't bring enough liquidity.
    function _ensureLiquidity(uint256 needed) internal {
        uint256 liquid = IERC20(asset()).balanceOf(address(this));
        if (liquid < needed && address(strategy) != address(0)) {
            uint256 deficit = needed - liquid;
            strategy.withdraw(deficit);
            require(
                IERC20(asset()).balanceOf(address(this)) >= needed, "YieldVault: insufficient liquidity after recall"
            );
        }
    }
}
