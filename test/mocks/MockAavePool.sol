// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal aToken for MockAavePool.
contract MockAToken is ERC20 {
    address public immutable pool;

    constructor() ERC20("Mock Aave aToken", "maUSDT") {
        pool = msg.sender;
    }

    modifier onlyPool() {
        require(msg.sender == pool, "MockAToken: only pool");
        _;
    }

    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyPool {
        _burn(from, amount);
    }
}

/// @notice Mock Aave V3 pool for testing AaveStrategy.
contract MockAavePool {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    MockAToken public immutable aToken;
    uint256 public withdrawBps = 10_000;

    constructor(address asset_) {
        asset = IERC20(asset_);
        aToken = new MockAToken();
    }

    function supply(address asset_, uint256 amount, address onBehalfOf, uint16) external {
        require(asset_ == address(asset), "MockAavePool: wrong asset");
        asset.safeTransferFrom(msg.sender, address(this), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address asset_, uint256 amount, address to) external returns (uint256 received) {
        require(asset_ == address(asset), "MockAavePool: wrong asset");
        aToken.burn(msg.sender, amount);
        received = (amount * withdrawBps) / 10_000;
        asset.safeTransfer(to, received);
    }

    function accrueYield(address account, uint256 amount) external {
        aToken.mint(account, amount);
    }

    function setWithdrawBps(uint256 bps) external {
        require(bps <= 10_000, "MockAavePool: bps too high");
        withdrawBps = bps;
    }
}
