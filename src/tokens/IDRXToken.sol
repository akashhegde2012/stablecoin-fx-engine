// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./StablecoinToken.sol";

/// @title IDRXToken
/// @notice ERC-20 stablecoin pegged 1:1 to the Indonesian Rupiah (IDR).
contract IDRXToken is StablecoinToken {
    constructor(address owner_) StablecoinToken("Indonesian Rupiah Stablecoin", "IDRX", 18, owner_) {}
}
