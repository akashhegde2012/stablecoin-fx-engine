// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./BaseStrategy.sol";
import "../interfaces/IAavePool.sol";

/**
 * @title AaveStrategy
 *  @notice Deploys idle stablecoins into an Aave V3 lending pool.
 *
 *          Flow
 *          ────
 *          deposit  → approve + supply to Aave Pool → receive aToken
 *          withdraw → Aave Pool.withdraw → aToken burned → underlying returned
 *          harvest  → aToken balance growth = yield → withdraw delta
 *
 *          The aToken balance grows automatically via Aave's rebasing mechanism,
 *          so `totalValue()` is simply the aToken balance.
 */
contract AaveStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IAavePool public immutable aavePool;
    IERC20 public immutable aToken;

    /// @dev Tracks principal so we can separate yield from deposits.
    uint256 public totalDeposited;

    constructor(address vault_, address asset_, address aavePool_, address aToken_) BaseStrategy(vault_, asset_) {
        require(aavePool_ != address(0), "AaveStrategy: zero pool");
        require(aToken_ != address(0), "AaveStrategy: zero aToken");
        aavePool = IAavePool(aavePool_);
        aToken = IERC20(aToken_);
    }

    // ── Views ───────────────────────────────────────────────────────────────

    function totalValue() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    // ── Hooks ───────────────────────────────────────────────────────────────

    function _afterDeposit(uint256 amount) internal override {
        IERC20(asset).forceApprove(address(aavePool), amount);
        aavePool.supply(asset, amount, address(this), 0);
        totalDeposited += amount;
    }

    function _beforeWithdraw(uint256 amount) internal override returns (uint256 received) {
        uint256 available = aToken.balanceOf(address(this));
        uint256 toWithdraw = amount > available ? available : amount;
        received = aavePool.withdraw(asset, toWithdraw, address(this));
        uint256 minReceived = (toWithdraw * (BPS - MAX_SLIPPAGE_BPS)) / BPS;
        require(received >= minReceived, "AaveStrategy: withdraw slippage");
        totalDeposited = totalDeposited > received ? totalDeposited - received : 0;
    }

    function _harvest() internal override returns (uint256 profit) {
        uint256 currentValue = aToken.balanceOf(address(this));
        if (currentValue > totalDeposited) {
            profit = currentValue - totalDeposited;
            aavePool.withdraw(asset, profit, address(this));
        }
    }
}
