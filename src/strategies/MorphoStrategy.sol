// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./BaseStrategy.sol";
import "../interfaces/IMorphoVault.sol";

/**
 * @title MorphoStrategy
 *  @notice Deploys idle stablecoins into a MetaMorpho (Morpho Blue) vault.
 *
 *          MetaMorpho vaults are curated ERC-4626 vaults that optimise lending
 *          rates across multiple Morpho Blue markets.  A vault curator selects
 *          and rebalances markets, so the strategy just deposits / withdraws.
 *
 *          Flow
 *          ────
 *          deposit  → approve + vault.deposit(assets) → receive vault shares
 *          withdraw → vault.withdraw(assets) → shares burned, underlying returned
 *          harvest  → (share value − principal) → withdraw the yield portion
 *          value    → vault.convertToAssets(shares)
 */
contract MorphoStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IMorphoVault public immutable morphoVault;

    uint256 public totalDeposited;

    constructor(address vault_, address asset_, address morphoVault_) BaseStrategy(vault_, asset_) {
        require(morphoVault_ != address(0), "MorphoStrategy: zero vault");
        morphoVault = IMorphoVault(morphoVault_);
    }

    // ── Views ───────────────────────────────────────────────────────────────

    function totalValue() external view override returns (uint256) {
        return _totalValue();
    }

    // ── Hooks ───────────────────────────────────────────────────────────────

    function _afterDeposit(uint256 amount) internal override {
        IERC20(asset).forceApprove(address(morphoVault), amount);
        uint256 expectedShares = morphoVault.convertToShares(amount);
        uint256 actualShares = morphoVault.deposit(amount, address(this));
        uint256 minShares = (expectedShares * (BPS - MAX_SLIPPAGE_BPS)) / BPS;
        require(actualShares >= minShares, "MorphoStrategy: deposit slippage");
        totalDeposited += amount;
    }

    function _beforeWithdraw(uint256 amount) internal override returns (uint256 received) {
        uint256 available = _totalValue();
        received = amount > available ? available : amount;
        morphoVault.withdraw(received, address(this), address(this));
        totalDeposited = totalDeposited > received ? totalDeposited - received : 0;
    }

    function _harvest() internal override returns (uint256 profit) {
        uint256 currentValue = _totalValue();
        if (currentValue > totalDeposited) {
            profit = currentValue - totalDeposited;
            morphoVault.withdraw(profit, address(this), address(this));
        }
    }

    // ── Internal ────────────────────────────────────────────────────────────

    function _totalValue() internal view returns (uint256) {
        return morphoVault.convertToAssets(morphoVault.balanceOf(address(this)));
    }
}
