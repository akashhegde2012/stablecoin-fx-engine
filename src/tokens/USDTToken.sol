// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StablecoinToken.sol";

/// @title USDTToken
/// @notice ERC-20 mock USDT token (18 decimals, pegged 1:1 to USD).
contract USDTToken is StablecoinToken {
    constructor(address owner_)
        StablecoinToken("Tether USD", "USDT", 18, owner_)
    {}
}
