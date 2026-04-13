// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFXPool.sol";
import "../oracles/OracleAggregator.sol";
import "./LPToken.sol";

/**
 @title FXPool
 @notice Single-sided liquidity pool for one stablecoin, priced via dual-oracle aggregator.
*/
contract FXPool is IFXPool, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_RATE = 1_000; // 10%

    IERC20 private immutable _stablecoin;
    LPToken private immutable _lpToken;
    OracleAggregator private immutable _oracle;

    address public fxEngine;
    uint256 public override feeRate;

    /**
    @param stablecoin_  Underlying ERC-20 stablecoin.
    @param oracle_      OracleAggregator address (dual Orakl + Pyth).
    @param lpName_      LP token name.
    @param lpSymbol_    LP token symbol.
    @param feeRate_     Initial fee (bps, e.g. 30 = 0.30%).
    @param owner_       Pool owner.
    */
    constructor(
        address stablecoin_,
        address oracle_,
        string memory lpName_,
        string memory lpSymbol_,
        uint256 feeRate_,
        address owner_
    ) Ownable(owner_) {
        require(stablecoin_ != address(0), "FXPool: zero stablecoin");
        require(oracle_ != address(0), "FXPool: zero oracle");
        require(feeRate_ <= MAX_FEE_RATE, "FXPool: fee too high");

        _stablecoin = IERC20(stablecoin_);
        _oracle = OracleAggregator(oracle_);
        feeRate = feeRate_;

        _lpToken = new LPToken(lpName_, lpSymbol_, address(this));
    }

    // -------------------------------------------------------------------------
    // IFXPool - LP actions
    // -------------------------------------------------------------------------

    function deposit(uint256 amount) external override nonReentrant returns (uint256 lpMinted) {
        require(amount > 0, "FXPool: zero amount");

        uint256 poolBalance = _stablecoin.balanceOf(address(this));
        uint256 totalLp = _lpToken.totalSupply();

        _stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        if (totalLp == 0 || poolBalance == 0) {
            lpMinted = amount;
        } else {
            lpMinted = (amount * totalLp) / poolBalance;
        }

        require(lpMinted > 0, "FXPool: zero lp minted");
        _lpToken.mint(msg.sender, lpMinted);

        emit Deposited(msg.sender, amount, lpMinted);
    }

    function withdraw(uint256 lpAmount) external override nonReentrant returns (uint256 amount) {
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

    function release(uint256 amount, address to) external override nonReentrant {
        require(msg.sender == fxEngine, "FXPool: only engine");
        require(to != address(0), "FXPool: zero recipient");
        require(amount <= _stablecoin.balanceOf(address(this)), "FXPool: insufficient liquidity");

        _stablecoin.safeTransfer(to, amount);
        emit Released(amount, to);
    }

    // Views

    /// @notice Latest USD price from the dual-oracle aggregator.
    function getPrice() external view override returns (int256 price, uint8 decimals_) {
        (price, decimals_) = _oracle.getPrice();
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

    function oracle() external view returns (address) {
        return address(_oracle);
    }

    function lpToStablecoinRate() external view returns (uint256) {
        uint256 totalLp = _lpToken.totalSupply();
        if (totalLp == 0) return 1e18;
        return (_stablecoin.balanceOf(address(this)) * 1e18) / totalLp;
    }

    // Owner admin

    function setFXEngine(address engine_) external onlyOwner {
        require(engine_ != address(0), "FXPool: zero engine");
        emit EngineUpdated(fxEngine, engine_);
        fxEngine = engine_;
    }

    function setFeeRate(uint256 feeRate_) external onlyOwner {
        require(feeRate_ <= MAX_FEE_RATE, "FXPool: fee too high");
        emit FeeRateUpdated(feeRate, feeRate_);
        feeRate = feeRate_;
    }
}
