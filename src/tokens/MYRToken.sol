// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StablecoinToken.sol";

/// @title MYRToken
/// @notice ERC-20 stablecoin pegged 1:1 to the Malaysian Ringgit (MYR).
contract MYRToken is StablecoinToken {
    constructor(address owner_)
        StablecoinToken("Malaysian Ringgit Stablecoin", "MYR", 18, owner_)
    {}
}
