// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IFXPool.sol";
import "./LPToken.sol";

/// @title FXPool
/// @notice Single-sided liquidity pool for one stablecoin.
///
///  ┌─────────────────────────────────────────────────────────────────┐
///  │  How it works                                                   │
///  │                                                                 │
///  │  • LPs deposit stablecoin X and receive wrapped-X (wX) tokens  │
///  │    proportional to their share of the pool.                     │
///  │                                                                 │
///  │  • During a swap the FXEngine sends tokenIn to the inPool      │
///  │    and calls release() on the outPool to send tokenOut to the  │
///  │    user.  A fee (feeRate bps) is deducted from the gross output │
///  │    and left inside the outPool, increasing the wX → X ratio    │
///  │    and thereby rewarding outPool LPs.                           │
///  │                                                                 │
///  │  • LPs withdraw by burning wX tokens and receiving a           │
///  │    proportional share of the pool balance (principal + fees).  │
///  └─────────────────────────────────────────────────────────────────┘
contract FXPool is IFXPool, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_RATE = 1_000; // 10 %

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    IERC20 private immutable _stablecoin;
    LPToken private immutable _lpToken;
    AggregatorV3Interface private immutable _priceFeed;
    uint8 private immutable _feedDecimals;

    address public fxEngine;
    uint256 public override feeRate; // in basis points, e.g. 30 = 0.30 %

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param stablecoin_  Address of the underlying ERC-20 stablecoin.
    /// @param priceFeed_   Chainlink-compatible price feed (token / USD).
    /// @param lpName_      Name for the LP token,   e.g. "Wrapped MYR".
    /// @param lpSymbol_    Symbol for the LP token, e.g. "wMYR".
    /// @param feeRate_     Initial fee in bps (30 = 0.30 %).
    /// @param owner_       Pool owner (can update feeRate and engine).
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
        _priceFeed = AggregatorV3Interface(priceFeed_);
        _feedDecimals = AggregatorV3Interface(priceFeed_).decimals();
        feeRate = feeRate_;

        // Deploy this pool's LP token; pool address is the owner
        _lpToken = new LPToken(lpName_, lpSymbol_, address(this));
    }

    // -------------------------------------------------------------------------
    // IFXPool – LP actions
    // -------------------------------------------------------------------------

    /// @inheritdoc IFXPool
    function deposit(uint256 amount) external override nonReentrant returns (uint256 lpMinted) {
        require(amount > 0, "FXPool: zero amount");

        uint256 poolBalance = _stablecoin.balanceOf(address(this));
        uint256 totalLp = _lpToken.totalSupply();

        // Transfer stablecoin from caller into pool before reading balances
        // (CEI: check → effect → interact ordering maintained by reading balances above)
        _stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        if (totalLp == 0 || poolBalance == 0) {
            // First deposit: mint 1 LP per stablecoin (1 : 1 bootstrap)
            lpMinted = amount;
        } else {
            // Subsequent deposits: proportional to current pool share
            lpMinted = (amount * totalLp) / poolBalance;
        }

        require(lpMinted > 0, "FXPool: zero lp minted");
        _lpToken.mint(msg.sender, lpMinted);

        emit Deposited(msg.sender, amount, lpMinted);
    }

    /// @inheritdoc IFXPool
    function withdraw(uint256 lpAmount) external override nonReentrant returns (uint256 amount) {
        require(lpAmount > 0, "FXPool: zero lp amount");

        uint256 poolBalance = _stablecoin.balanceOf(address(this));
        uint256 totalLp = _lpToken.totalSupply();
        require(totalLp > 0, "FXPool: no liquidity");

        // Pro-rata share of pool (includes accumulated fees)
        amount = (lpAmount * poolBalance) / totalLp;
        require(amount > 0, "FXPool: zero withdrawal");

        _lpToken.burn(msg.sender, lpAmount);
        _stablecoin.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, lpAmount, amount);
    }

    // -------------------------------------------------------------------------
    // IFXPool – Engine-only
    // -------------------------------------------------------------------------

    /// @inheritdoc IFXPool
    function release(uint256 amount, address to) external override nonReentrant {
        require(msg.sender == fxEngine, "FXPool: only engine");
        require(to != address(0), "FXPool: zero recipient");
        require(amount <= _stablecoin.balanceOf(address(this)), "FXPool: insufficient liquidity");

        _stablecoin.safeTransfer(to, amount);
        emit Released(amount, to);
    }

    // -------------------------------------------------------------------------
    // IFXPool – Views
    // -------------------------------------------------------------------------

    /// @inheritdoc IFXPool
    function getPrice() external view override returns (int256 price, uint8 decimals_) {
        (, price,,,) = _priceFeed.latestRoundData();
        require(price > 0, "FXPool: invalid price");
        decimals_ = _feedDecimals;
    }

    /// @inheritdoc IFXPool
    function getPoolBalance() external view override returns (uint256) {
        return _stablecoin.balanceOf(address(this));
    }

    /// @inheritdoc IFXPool
    function lpToken() external view override returns (address) {
        return address(_lpToken);
    }

    /// @inheritdoc IFXPool
    function stablecoin() external view override returns (address) {
        return address(_stablecoin);
    }

    /// @notice Exchange rate: how many stablecoins per 1e18 LP token.
    function lpToStablecoinRate() external view returns (uint256) {
        uint256 totalLp = _lpToken.totalSupply();
        if (totalLp == 0) return 1e18;
        return (_stablecoin.balanceOf(address(this)) * 1e18) / totalLp;
    }

    // -------------------------------------------------------------------------
    // Owner admin
    // -------------------------------------------------------------------------

    /// @notice Set the authorised FXEngine. Only callable by the owner.
    function setFXEngine(address engine_) external onlyOwner {
        require(engine_ != address(0), "FXPool: zero engine");
        emit EngineUpdated(fxEngine, engine_);
        fxEngine = engine_;
    }

    /// @notice Update the swap fee rate. Only callable by the owner.
    function setFeeRate(uint256 feeRate_) external onlyOwner {
        require(feeRate_ <= MAX_FEE_RATE, "FXPool: fee too high");
        emit FeeRateUpdated(feeRate, feeRate_);
        feeRate = feeRate_;
    }
}
