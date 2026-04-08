// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../src/interfaces/IYieldStrategy.sol";

/// @notice Deterministic mock strategy for testing YieldVault.
///         Holds tokens directly and allows a test harness to simulate yield
///         by minting extra tokens to this contract.
contract MockStrategy is IYieldStrategy {
    using SafeERC20 for IERC20;

    address public override vault;
    address public override asset;
    uint256 public deposited;

    constructor(address vault_, address asset_) {
        vault = vault_;
        asset = asset_;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "MockStrategy: only vault");
        _;
    }

    function deposit(uint256 amount) external override onlyVault {
        IERC20(asset).safeTransferFrom(vault, address(this), amount);
        deposited += amount;
        emit Deposited(amount);
    }

    function withdraw(uint256 amount) external override onlyVault returns (uint256 received) {
        uint256 bal = IERC20(asset).balanceOf(address(this));
        received = amount > bal ? bal : amount;
        IERC20(asset).safeTransfer(vault, received);
        deposited = deposited > received ? deposited - received : 0;
        emit Withdrawn(amount, received);
    }

    function harvest() external override onlyVault returns (uint256 profit) {
        uint256 bal = IERC20(asset).balanceOf(address(this));
        if (bal > deposited) {
            profit = bal - deposited;
            IERC20(asset).safeTransfer(vault, profit);
        }
        emit Harvested(profit);
    }

    function totalValue() external view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
}
