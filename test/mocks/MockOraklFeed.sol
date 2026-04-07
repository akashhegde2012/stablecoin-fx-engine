// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IOraklFeed.sol";

/// @notice Test mock implementing the Orakl v0.2 feed interface.
contract MockOraklFeed is IOraklFeed {
    uint8 private _decimals;
    int256 private _answer;

    constructor(uint8 decimals_, int256 answer_) {
        _decimals = decimals_;
        _answer = answer_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData() external view override returns (uint64 id, int256 answer, uint256 updatedAt) {
        return (1, _answer, block.timestamp);
    }

    function updateAnswer(int256 answer_) external {
        _answer = answer_;
    }
}
