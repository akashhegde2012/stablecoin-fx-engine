// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IYieldStrategy
/// @notice Common interface for all yield-generating strategy adapters.
///         Each strategy wraps a single DeFi protocol (Aave, Pendle, Morpho, …)
///         and is owned by exactly one YieldVault.
interface IYieldStrategy {
    event Deposited(uint256 amount);
    event Withdrawn(uint256 requested, uint256 received);
    event Harvested(uint256 profit);

    /// @notice Deploy `amount` of the underlying asset into the protocol.
    function deposit(uint256 amount) external;

    /// @notice Recall up to `amount` of the underlying asset from the protocol.
    /// @return received Actual amount returned (may differ due to slippage / rounding).
    function withdraw(uint256 amount) external returns (uint256 received);

    /// @notice Realise accrued yield and send it back to the vault.
    /// @return profit Amount of underlying asset harvested.
    function harvest() external returns (uint256 profit);

    /// @notice Current value of all assets managed by this strategy (principal + yield).
    function totalValue() external view returns (uint256);

    /// @notice The ERC-20 asset this strategy operates on.
    function asset() external view returns (address);

    /// @notice The vault that owns this strategy.
    function vault() external view returns (address);
}
