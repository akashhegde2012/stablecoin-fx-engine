// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

/// @title MintToWallet
/// @notice Mints a generous test allocation of each stablecoin to any address.
///
///  Usage:
///
///    forge script script/MintToWallet.s.sol \
///      --fork-url http://127.0.0.1:8545 \
///      --broadcast \
///      --private-key <DEPLOYER_KEY> \
///      --sig "run(address)" <RECIPIENT_ADDRESS>
///
///  The deployer key must be the owner of each token contract
///  (i.e. the same key used in Deploy.s.sol).
///
///  Mint amounts (≈ equivalent USD value each):
///    10 000 USDT   → $10 000
///    44 092 MYR    → $10 000  (1 USD = 4.41 MYR)
///    13 479 SGD    → $10 000  (1 USD = 1.35 SGD)
///    162 074 550 IDRX → $10 000  (1 USD = 16 207 IDR)
contract MintToWallet is Script {
    // ── Deployed token addresses (from Deploy.s.sol output) ────────────────
    address constant MYR_ADDR = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant SGD_ADDR = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address constant IDRX_ADDR = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address constant USDT_ADDR = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;

    // ── Mint amounts (18 decimals) ─────────────────────────────────────────
    uint256 constant USDT_AMOUNT = 10_000 ether;
    uint256 constant MYR_AMOUNT = 44_092 ether;
    uint256 constant SGD_AMOUNT = 13_479 ether;
    uint256 constant IDRX_AMOUNT = 162_074_550 ether;

    function run(address recipient) external {
        require(recipient != address(0), "MintToWallet: zero recipient");

        vm.startBroadcast();

        MYRToken(MYR_ADDR).mint(recipient, MYR_AMOUNT);
        SGDToken(SGD_ADDR).mint(recipient, SGD_AMOUNT);
        IDRXToken(IDRX_ADDR).mint(recipient, IDRX_AMOUNT);
        USDTToken(USDT_ADDR).mint(recipient, USDT_AMOUNT);

        vm.stopBroadcast();

        console.log("=== Minted to", recipient, "===");
        console.log("USDT :", USDT_AMOUNT / 1 ether, "USDT");
        console.log("MYR  :", MYR_AMOUNT / 1 ether, "MYR");
        console.log("SGD  :", SGD_AMOUNT / 1 ether, "SGD");
        console.log("IDRX :", IDRX_AMOUNT / 1 ether, "IDRX");
    }
}
