// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFXPool
 *  @notice Interface for a single-sided FX liquidity pool
 */
interface IFXPool {
    // Events
    event Deposited(address indexed user, uint256 amount, uint256 lpMinted);
    event Withdrawn(address indexed user, uint256 lpBurned, uint256 amount);
    event Released(uint256 amount, address indexed to);
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);
    event EngineProposed(address indexed proposedEngine);

    // LP actions

    /// @notice Deposit stablecoins and receive LP tokens representing pool share.
    /// @param amount   Amount of underlying stablecoin to deposit (18 dec).
    /// @return lpMinted LP tokens minted to the caller.
    function deposit(uint256 amount) external returns (uint256 lpMinted);

    /// @notice Burn LP tokens and withdraw the proportional underlying stablecoin.
    /// @param lpAmount LP tokens to burn.
    /// @return amount  Underlying stablecoins returned to the caller.
    function withdraw(uint256 lpAmount) external returns (uint256 amount);

    // Engine-only

    /// @notice Transfer `amount` of the pool's stablecoin to `to`.
    ///         Called exclusively by the authorised FXEngine during a swap.
    function release(uint256 amount, address to) external;

    // Views

    /// @notice Latest USD price from the Pyth feed, plus the feed's decimal precision.
    function getPrice() external view returns (int256 price, uint8 decimals);

    /// @notice Current stablecoin balance held by the pool.
    function getPoolBalance() external view returns (uint256);

    /// @notice Fee rate charged on the gross output amount, in basis points (e.g. 30 = 0.30%).
    function feeRate() external view returns (uint256);

    /// @notice The LP token address for this pool.
    function lpToken() external view returns (address);

    /// @notice The underlying stablecoin address.
    function stablecoin() external view returns (address);
}
