// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** @title IFXPool
 @notice Interface for a single-sided FX liquidity pool
*/
interface IFXPool {
    // Events
    event Deposited(address indexed user, uint256 amount, uint256 lpMinted);
    event Withdrawn(address indexed user, uint256 lpBurned, uint256 amount);
    event Released(uint256 amount, address indexed to);
    event PlatformFeeDistributed(uint256 amount, address indexed treasury);
    event BaseFeeRateUpdated(uint256 oldRate, uint256 newRate);
    event UtilizationFactorUpdated(uint256 oldFactor, uint256 newFactor);
    event MaxDynamicFeeRateUpdated(uint256 oldMax, uint256 newMax);
    event PlatformFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event PlatformTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event EngineUpdated(address indexed oldEngine, address indexed newEngine);

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

    /// @notice Transfer platform fee portion to the treasury address.
    ///         Called by FXEngine after a swap to distribute the platform's fee share.
    function releasePlatformFee(uint256 amount) external;

    // Views

    /// @notice Latest USD price from the Pyth feed, plus the feed's decimal precision.
    function getPrice() external view returns (int256 price, uint8 decimals);

    /// @notice Current stablecoin balance held by the pool.
    function getPoolBalance() external view returns (uint256);

    /// @notice Base fee rate in basis points (minimum fee, e.g. 10 = 0.10%).
    function feeRate() external view returns (uint256);

    /// @notice Compute the dynamic fee rate for a given trade size, in basis points.
    ///         Utilization-based: fee increases with grossOut relative to pool balance.
    /// @param grossOutAmount  Gross output amount of the swap (before fees).
    /// @return effectiveFeeRate  Fee rate in bps, capped at maxDynamicFeeRate.
    function getEffectiveFeeRate(uint256 grossOutAmount) external view returns (uint256);

    /// @notice Maximum dynamic fee rate cap in basis points.
    function maxDynamicFeeRate() external view returns (uint256);

    /// @notice Platform fee share in basis points of total fee (e.g. 3000 = 30%).
    function platformFeeBps() external view returns (uint256);

    /// @notice Platform treasury address that receives platform fees.
    function platformTreasury() external view returns (address);

    /// @notice The LP token address for this pool.
    function lpToken() external view returns (address);

    /// @notice The underlying stablecoin address.
    function stablecoin() external view returns (address);
}
