// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./BaseStrategy.sol";
import "../interfaces/IPendleSYToken.sol";

/**
 * @title PendleStrategy
 *  @notice Deploys idle stablecoins into a Pendle Standardized Yield (SY) token.
 *
 *          Pendle SY tokens are yield-bearing wrappers around external protocols
 *          (e.g. SY-aUSDT wraps Aave's aUSDT).  Depositing underlying into the
 *          SY token earns the same yield as the wrapped protocol, while also
 *          enabling Pendle yield-tokenization (PT/YT) in downstream markets.
 *
 *          Flow
 *          ────
 *          deposit  → approve + SY.deposit(underlying) → receive SY shares
 *          withdraw → SY.redeem(shares) → receive underlying
 *          harvest  → (SY value − principal) → redeem the yield portion
 *          value    → SY balance × exchangeRate
 */
contract PendleStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IPendleSYToken public immutable syToken;

    uint256 public totalDeposited;

    constructor(address vault_, address asset_, address syToken_) BaseStrategy(vault_, asset_) {
        require(syToken_ != address(0), "PendleStrategy: zero SY");
        syToken = IPendleSYToken(syToken_);
    }

    // ── Views ───────────────────────────────────────────────────────────────

    function totalValue() external view override returns (uint256) {
        return _totalValue();
    }

    // ── Hooks ───────────────────────────────────────────────────────────────

    function _afterDeposit(uint256 amount) internal override {
        IERC20(asset).forceApprove(address(syToken), amount);
        uint256 rate = syToken.exchangeRate();
        uint256 expectedShares = (amount * 1e18) / rate;
        uint256 minShares = (expectedShares * (BPS - MAX_SLIPPAGE_BPS)) / BPS;
        syToken.deposit(address(this), asset, amount, minShares);
        totalDeposited += amount;
    }

    function _beforeWithdraw(uint256 amount) internal override returns (uint256 received) {
        uint256 rate = syToken.exchangeRate();
        uint256 sharesToRedeem = (amount * 1e18) / rate;

        uint256 available = syToken.balanceOf(address(this));
        if (sharesToRedeem > available) sharesToRedeem = available;

        uint256 minTokens = (sharesToRedeem * rate) / 1e18;
        minTokens = (minTokens * (BPS - MAX_SLIPPAGE_BPS)) / BPS;
        received = syToken.redeem(address(this), sharesToRedeem, asset, minTokens, false);
        totalDeposited = totalDeposited > received ? totalDeposited - received : 0;
    }

    function _harvest() internal override returns (uint256 profit) {
        uint256 currentValue = _totalValue();
        if (currentValue > totalDeposited) {
            profit = currentValue - totalDeposited;
            uint256 rate = syToken.exchangeRate();
            uint256 sharesToRedeem = (profit * 1e18) / rate;

            uint256 available = syToken.balanceOf(address(this));
            if (sharesToRedeem > available) sharesToRedeem = available;

            uint256 minTokens = (sharesToRedeem * rate) / 1e18;
            minTokens = (minTokens * (BPS - MAX_SLIPPAGE_BPS)) / BPS;
            profit = syToken.redeem(address(this), sharesToRedeem, asset, minTokens, false);
        }
    }

    // ── Internal ────────────────────────────────────────────────────────────

    function _totalValue() internal view returns (uint256) {
        uint256 syBalance = syToken.balanceOf(address(this));
        return (syBalance * syToken.exchangeRate()) / 1e18;
    }
}
