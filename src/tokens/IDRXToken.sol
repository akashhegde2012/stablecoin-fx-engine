// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StablecoinToken.sol";

/// @title IDRXToken
/// @notice ERC-20 stablecoin pegged 1:1 to the Indonesian Rupiah (IDR).
///         1 IDRX = 1 IDR ≈ 0.0000617 USD  (1 USD ≈ 16,207 IDRX).
contract IDRXToken is StablecoinToken {
    constructor(address owner_)
        StablecoinToken("Indonesian Rupiah Stablecoin", "IDRX", 18, owner_)
    {}
}
