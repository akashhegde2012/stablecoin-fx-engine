// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal interface for an Orakl Network v0.2 data feed (proxy or direct).
///         latestRoundData returns (roundId, answer, updatedAt) — 3 values, not 5.
interface IOraklFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint64 id, int256 answer, uint256 updatedAt);
}
