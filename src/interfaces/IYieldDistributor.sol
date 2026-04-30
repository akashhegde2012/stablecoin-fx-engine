// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IYieldDistributor
/// @notice Minimal interface used by FXEngine and YieldVault to push fee
///         notifications into the distributor.  The full contract exposes
///         staking, claiming, and bonus-reward management on top of this.
interface IYieldDistributor {
    /// @notice Called after protocol fees have been transferred to this contract.
    /// @param vault  The vault (pool) the fee belongs to.
    /// @param amount The fee amount (in the vault's underlying stablecoin).
    function notifyFees(address vault, uint256 amount) external;
}
