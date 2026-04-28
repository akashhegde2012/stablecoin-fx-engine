// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IOraklFeed.sol";
import "../interfaces/IFXPool.sol";
import "./LPToken.sol";

/**
 * @title FXPool
 *  @notice Single-sided liquidity pool for one stablecoin, priced via Orakl Network.
 */
contract FXPool is IFXPool, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_RATE = 1_000; // 10%

    /// @notice Permanently locked LP tokens on first deposit to prevent inflation attacks.
    uint256 public constant MINIMUM_LIQUIDITY = 1_000;

    IERC20 private immutable _stablecoin;
    LPToken private immutable _lpToken;
    IOraklFeed private immutable _priceFeed;
    uint8 private immutable _feedDecimals;

    address public fxEngine;
    address public pendingFxEngine;
    uint256 public override feeRate;

    /// @notice Max allowed age (seconds) for oracle data before it's considered stale.
    uint256 public maxStaleness = 3600;

    constructor(
        address stablecoin_,
        address priceFeed_,
        string memory lpName_,
        string memory lpSymbol_,
        uint256 feeRate_,
        address owner_
    ) Ownable(owner_) {
        require(stablecoin_ != address(0), "FXPool: zero stablecoin");
        require(priceFeed_ != address(0), "FXPool: zero priceFeed");
        require(feeRate_ <= MAX_FEE_RATE, "FXPool: fee too high");

        _stablecoin = IERC20(stablecoin_);
        _priceFeed = IOraklFeed(priceFeed_);
        _feedDecimals = IOraklFeed(priceFeed_).decimals();
        feeRate = feeRate_;

        _lpToken = new LPToken(lpName_, lpSymbol_, address(this));
    }

    // -------------------------------------------------------------------------
    // IFXPool - LP actions
    // -------------------------------------------------------------------------

    function deposit(uint256 amount) external override nonReentrant whenNotPaused returns (uint256 lpMinted) {
        require(amount > 0, "FXPool: zero amount");

        uint256 poolBalance = _stablecoin.balanceOf(address(this));
        uint256 totalLp = _lpToken.totalSupply();

        _stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        if (totalLp == 0 || poolBalance == 0) {
            lpMinted = amount;
            require(lpMinted > MINIMUM_LIQUIDITY, "FXPool: initial deposit too small");
            _lpToken.mint(address(0xdead), MINIMUM_LIQUIDITY);
            lpMinted -= MINIMUM_LIQUIDITY;
        } else {
            lpMinted = (amount * totalLp) / poolBalance;
        }

        require(lpMinted > 0, "FXPool: zero lp minted");
        _lpToken.mint(msg.sender, lpMinted);

        emit Deposited(msg.sender, amount, lpMinted);
    }

    function withdraw(uint256 lpAmount) external override nonReentrant whenNotPaused returns (uint256 amount) {
        require(lpAmount > 0, "FXPool: zero lp amount");

        uint256 poolBalance = _stablecoin.balanceOf(address(this));
        uint256 totalLp = _lpToken.totalSupply();
        require(totalLp > 0, "FXPool: no liquidity");

        amount = (lpAmount * poolBalance) / totalLp;
        require(amount > 0, "FXPool: zero withdrawal");

        _lpToken.burn(msg.sender, lpAmount);
        _stablecoin.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, lpAmount, amount);
    }

    // Engine-only

    function release(uint256 amount, address to) external override nonReentrant whenNotPaused {
        require(msg.sender == fxEngine, "FXPool: only engine");
        require(to != address(0), "FXPool: zero recipient");
        require(amount <= _stablecoin.balanceOf(address(this)), "FXPool: insufficient liquidity");

        _stablecoin.safeTransfer(to, amount);
        emit Released(amount, to);
    }

    // Views

    function getPrice() external view override returns (int256 price, uint8 decimals_) {
        uint256 updatedAt;
        (, price, updatedAt) = _priceFeed.latestRoundData();
        require(price > 0, "FXPool: invalid price");
        require(block.timestamp - updatedAt <= maxStaleness, "FXPool: stale price");
        decimals_ = _feedDecimals;
    }

    function getPoolBalance() external view override returns (uint256) {
        return _stablecoin.balanceOf(address(this));
    }

    function lpToken() external view override returns (address) {
        return address(_lpToken);
    }

    function stablecoin() external view override returns (address) {
        return address(_stablecoin);
    }

    function lpToStablecoinRate() external view returns (uint256) {
        uint256 totalLp = _lpToken.totalSupply();
        if (totalLp == 0) return 1e18;
        return (_stablecoin.balanceOf(address(this)) * 1e18) / totalLp;
    }

    // -------------------------------------------------------------------------
    // Owner admin
    // -------------------------------------------------------------------------

    /// @notice Propose a new FX engine. Must be accepted via acceptEngine().
    function proposeEngine(address engine_) external onlyOwner {
        require(engine_ != address(0), "FXPool: zero engine");
        pendingFxEngine = engine_;
        emit EngineProposed(engine_);
    }

    /// @notice Accept a previously proposed engine, activating it.
    function acceptEngine() external onlyOwner {
        address pending = pendingFxEngine;
        require(pending != address(0), "FXPool: no pending engine");
        emit EngineUpdated(fxEngine, pending);
        fxEngine = pending;
        pendingFxEngine = address(0);
    }

    function setFeeRate(uint256 feeRate_) external onlyOwner {
        require(feeRate_ <= MAX_FEE_RATE, "FXPool: fee too high");
        emit FeeRateUpdated(feeRate, feeRate_);
        feeRate = feeRate_;
    }

    function setMaxStaleness(uint256 staleness_) external onlyOwner {
        require(staleness_ >= 60, "FXPool: staleness too short");
        maxStaleness = staleness_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
