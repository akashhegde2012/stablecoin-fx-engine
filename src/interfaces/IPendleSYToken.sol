// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Pendle Standardized Yield (SY) token interface.
///         SY wraps yield-bearing assets into a common interface that
///         Pendle uses for yield tokenization (PT / YT splitting).
///         Only the methods used by PendleStrategy are included.
interface IPendleSYToken {
    /// @notice Deposit `amountTokenToDeposit` of `tokenIn` and receive SY shares.
    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        returns (uint256 amountSharesOut);

    /// @notice Redeem `amountSharesToRedeem` SY shares for `tokenOut`.
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    /// @notice Current exchange rate from SY shares to underlying (1e18 = 1:1).
    function exchangeRate() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
