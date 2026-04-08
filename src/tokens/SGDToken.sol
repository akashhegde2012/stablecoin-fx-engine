// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StablecoinToken.sol";

/// @title SGDToken
/// @notice ERC-20 stablecoin pegged 1:1 to the Singapore Dollar (SGD).
contract SGDToken is StablecoinToken {
    constructor(address owner_) StablecoinToken("Singapore Dollar Stablecoin", "SGD", 18, owner_) {}
}
