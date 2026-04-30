// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock MetaMorpho vault for testing MorphoStrategy.
///         Share price is derived from (underlying balance / total supply),
///         so minting extra underlying to this contract simulates yield.
contract MockMorphoVault is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;

    constructor(address asset_) ERC20("Mock Morpho Vault", "mMV") {
        asset = IERC20(asset_);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner_) external returns (uint256 shares) {
        shares = convertToShares(assets);
        _burn(owner_, shares);
        asset.safeTransfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner_) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        _burn(owner_, shares);
        asset.safeTransfer(receiver, assets);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        return (shares * asset.balanceOf(address(this))) / supply;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 bal = asset.balanceOf(address(this));
        if (supply == 0 || bal == 0) return assets;
        return (assets * supply) / bal;
    }
}
