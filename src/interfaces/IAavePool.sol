// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Aave V3 Pool interface — only the methods used by AaveStrategy.
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
