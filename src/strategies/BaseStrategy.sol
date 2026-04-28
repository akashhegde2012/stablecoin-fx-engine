// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IYieldStrategy.sol";

/**
 * @title BaseStrategy
 *  @notice Abstract skeleton for yield strategy adapters.
 *
 *          Concrete strategies (AaveStrategy, PendleStrategy, …) override
 *          three internal hooks:
 *            _afterDeposit   – deploy assets into the protocol
 *            _beforeWithdraw – recall assets from the protocol
 *            _harvest        – realise accrued yield
 *
 *          All external entry points are restricted to the owning vault.
 */
abstract contract BaseStrategy is IYieldStrategy {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_SLIPPAGE_BPS = 50; // 0.5%
    uint256 internal constant BPS = 10_000;

    address public immutable override vault;
    address public immutable override asset;

    modifier onlyVault() {
        require(msg.sender == vault, "BaseStrategy: only vault");
        _;
    }

    constructor(address vault_, address asset_) {
        require(vault_ != address(0), "BaseStrategy: zero vault");
        require(asset_ != address(0), "BaseStrategy: zero asset");
        vault = vault_;
        asset = asset_;
    }

    // ── External (vault-only) ───────────────────────────────────────────────

    function deposit(uint256 amount) external override onlyVault {
        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        _afterDeposit(amount);
        emit Deposited(amount);
    }

    function withdraw(uint256 amount) external override onlyVault returns (uint256 received) {
        received = _beforeWithdraw(amount);
        IERC20(asset).safeTransfer(vault, received);
        emit Withdrawn(amount, received);
    }

    function harvest() external override onlyVault returns (uint256 profit) {
        profit = _harvest();
        if (profit > 0) {
            IERC20(asset).safeTransfer(vault, profit);
        }
        emit Harvested(profit);
    }

    // ── Hooks for concrete strategies ───────────────────────────────────────

    /// @dev Deploy `amount` of the underlying into the external protocol.
    function _afterDeposit(uint256 amount) internal virtual;

    /// @dev Recall up to `amount` from the external protocol.
    /// @return received Actual underlying tokens now held by this contract.
    function _beforeWithdraw(uint256 amount) internal virtual returns (uint256 received);

    /// @dev Realise accrued yield. Return the underlying profit amount
    ///      that is currently held by this contract and ready to transfer.
    function _harvest() internal virtual returns (uint256 profit);
}
