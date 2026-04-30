// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal MetaMorpho vault interface (ERC-4626 subset).
///         MetaMorpho vaults are curated lending vaults on top of Morpho Blue
///         that optimise rates across multiple lending markets.
///         Only the methods used by MorphoStrategy are included.
interface IMorphoVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function asset() external view returns (address);
}
