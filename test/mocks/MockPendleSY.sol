// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Mock Pendle SY token for testing PendleStrategy.
///         Simulates a yield-bearing wrapper with a settable exchange rate.
///         To simulate yield: mint extra underlying to this contract AND
///         increase `exchangeRate` proportionally.
contract MockPendleSY is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public underlying;
    uint256 public exchangeRate = 1e18;

    constructor(address underlying_) ERC20("Mock Pendle SY", "mSY") {
        underlying = IERC20(underlying_);
    }

    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 /* minSharesOut */ )
        external
        returns (uint256 amountSharesOut)
    {
        require(tokenIn == address(underlying), "MockPendleSY: wrong token");
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountTokenToDeposit);
        amountSharesOut = (amountTokenToDeposit * 1e18) / exchangeRate;
        _mint(receiver, amountSharesOut);
    }

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256, /* minTokenOut */
        bool /* burnFromInternalBalance */
    ) external returns (uint256 amountTokenOut) {
        require(tokenOut == address(underlying), "MockPendleSY: wrong token");
        amountTokenOut = (amountSharesToRedeem * exchangeRate) / 1e18;
        _burn(msg.sender, amountSharesToRedeem);
        underlying.safeTransfer(receiver, amountTokenOut);
    }

    /// @dev Call this + mint underlying to simulate yield accrual.
    function setExchangeRate(uint256 rate_) external {
        exchangeRate = rate_;
    }
}
