// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "@chainlink/contracts/tests/MockV3Aggregator.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

import "../src/pools/FXPool.sol";
import "../src/FXEngine.sol";

/// @title Deploy
/// @notice Full deployment on a local Anvil fork.
///
///  Mock Chainlink price feeds are seeded with real-world approximate values
///  (February 2026, 8-decimal USD feeds):
///
///  Token   Symbol  Price (USD)  Feed answer (8 dec)
///  ──────────────────────────────────────────────────
///  MYR     MYR     0.2268       22_680_000
///  SGD     SGD     0.7419       74_190_000
///  IDRX    IDRX    0.0000617     6_170
///  USDT    USDT    1.0000      100_000_000
///
///  Initial pool liquidity (seeded by the deployer) is sized so that all pools
///  hold roughly equivalent USD value (≈ $1 000 000 each):
///
///  Pool     Initial balance
///  ────────────────────────
///  MYR      4 409 171 MYR   ($1M / $0.2268)
///  SGD      1 347 891 SGD   ($1M / $0.7419)
///  IDRX    16 207 455 000 IDRX ($1M / $0.0000617)
///  USDT     1 000 000 USDT
contract Deploy is Script {
    // ── Chainlink price feed answers (8 decimals) ──────────────────────────────
    int256 constant MYR_USD_PRICE  = 22_680_000;    // $0.2268
    int256 constant SGD_USD_PRICE  = 74_190_000;    // $0.7419
    int256 constant IDRX_USD_PRICE =      6_170;    // $0.0000617
    int256 constant USDT_USD_PRICE = 100_000_000;   // $1.0000

    // ── Pool seed liquidity ────────────────────────────────────────────────────
    uint256 constant MYR_SEED   =    4_409_171 ether; //  4.4M  MYR
    uint256 constant SGD_SEED   =    1_347_891 ether; //  1.3M  SGD
    uint256 constant IDRX_SEED  = 16_207_455_000 ether; // 16.2B IDRX
    uint256 constant USDT_SEED  =    1_000_000 ether; //  1M    USDT

    // ── Additional tokens minted to deployer for testing ─────────────────────
    uint256 constant TEST_MYR   =      500_000 ether;
    uint256 constant TEST_SGD   =      150_000 ether;
    uint256 constant TEST_IDRX  = 1_620_745_000 ether;
    uint256 constant TEST_USDT  =      100_000 ether;

    // ── Swap fee: 0.30 % ──────────────────────────────────────────────────────
    uint256 constant FEE_RATE = 30; // bps

    function run() external {
        // Pass the key via CLI:  --private-key <key>
        // msg.sender inside broadcast == the key's address
        vm.startBroadcast();
        address deployer = msg.sender;

        // ── 1. Deploy mock stablecoins ─────────────────────────────────────────
        MYRToken  myr  = new MYRToken(deployer);
        SGDToken  sgd  = new SGDToken(deployer);
        IDRXToken idrx = new IDRXToken(deployer);
        USDTToken usdt = new USDTToken(deployer);

        console.log("=== Stablecoin Tokens ===");
        console.log("MYR  :", address(myr));
        console.log("SGD  :", address(sgd));
        console.log("IDRX :", address(idrx));
        console.log("USDT :", address(usdt));

        // ── 2. Deploy mock Chainlink price feeds ───────────────────────────────
        MockV3Aggregator myrFeed  = new MockV3Aggregator(8, MYR_USD_PRICE);
        MockV3Aggregator sgdFeed  = new MockV3Aggregator(8, SGD_USD_PRICE);
        MockV3Aggregator idrxFeed = new MockV3Aggregator(8, IDRX_USD_PRICE);
        MockV3Aggregator usdtFeed = new MockV3Aggregator(8, USDT_USD_PRICE);

        console.log("\n=== Chainlink Mock Price Feeds (token/USD, 8 dec) ===");
        console.log("MYR  feed:", address(myrFeed),  "  price:", uint256(MYR_USD_PRICE));
        console.log("SGD  feed:", address(sgdFeed),  "  price:", uint256(SGD_USD_PRICE));
        console.log("IDRX feed:", address(idrxFeed), "  price:", uint256(IDRX_USD_PRICE));
        console.log("USDT feed:", address(usdtFeed), "  price:", uint256(USDT_USD_PRICE));

        // ── 3. Deploy FX liquidity pools ───────────────────────────────────────
        FXPool myrPool  = new FXPool(address(myr),  address(myrFeed),  "Wrapped MYR",  "wMYR",  FEE_RATE, deployer);
        FXPool sgdPool  = new FXPool(address(sgd),  address(sgdFeed),  "Wrapped SGD",  "wSGD",  FEE_RATE, deployer);
        FXPool idrxPool = new FXPool(address(idrx), address(idrxFeed), "Wrapped IDRX", "wIDRX", FEE_RATE, deployer);
        FXPool usdtPool = new FXPool(address(usdt), address(usdtFeed), "Wrapped USDT", "wUSDT", FEE_RATE, deployer);

        console.log("\n=== FX Pools ===");
        console.log("MYR  pool:", address(myrPool),  "  lpToken:", myrPool.lpToken());
        console.log("SGD  pool:", address(sgdPool),  "  lpToken:", sgdPool.lpToken());
        console.log("IDRX pool:", address(idrxPool), "  lpToken:", idrxPool.lpToken());
        console.log("USDT pool:", address(usdtPool), "  lpToken:", usdtPool.lpToken());

        // ── 4. Deploy FX Engine and wire pools ─────────────────────────────────
        FXEngine engine = new FXEngine(deployer);
        engine.registerPool(address(myr),  address(myrPool));
        engine.registerPool(address(sgd),  address(sgdPool));
        engine.registerPool(address(idrx), address(idrxPool));
        engine.registerPool(address(usdt), address(usdtPool));

        console.log("\n=== FX Engine ===");
        console.log("FXEngine:", address(engine));

        // ── 5. Authorise the engine in every pool ─────────────────────────────
        myrPool.setFXEngine(address(engine));
        sgdPool.setFXEngine(address(engine));
        idrxPool.setFXEngine(address(engine));
        usdtPool.setFXEngine(address(engine));

        // ── 6. Mint tokens (pool seed + tester allocation) ────────────────────
        myr.mint(deployer,  MYR_SEED  + TEST_MYR);
        sgd.mint(deployer,  SGD_SEED  + TEST_SGD);
        idrx.mint(deployer, IDRX_SEED + TEST_IDRX);
        usdt.mint(deployer, USDT_SEED + TEST_USDT);

        // ── 7. Approve pools and seed initial liquidity ───────────────────────
        myr.approve(address(myrPool),   MYR_SEED);
        sgd.approve(address(sgdPool),   SGD_SEED);
        idrx.approve(address(idrxPool), IDRX_SEED);
        usdt.approve(address(usdtPool), USDT_SEED);

        uint256 myrLp  = myrPool.deposit(MYR_SEED);
        uint256 sgdLp  = sgdPool.deposit(SGD_SEED);
        uint256 idrxLp = idrxPool.deposit(IDRX_SEED);
        uint256 usdtLp = usdtPool.deposit(USDT_SEED);

        console.log("\n=== Initial Liquidity Seeded ===");
        console.log("MYR  pool balance:", myrPool.getPoolBalance(),  "  wMYR  minted:", myrLp);
        console.log("SGD  pool balance:", sgdPool.getPoolBalance(),  "  wSGD  minted:", sgdLp);
        console.log("IDRX pool balance:", idrxPool.getPoolBalance(), "  wIDRX minted:", idrxLp);
        console.log("USDT pool balance:", usdtPool.getPoolBalance(), "  wUSDT minted:", usdtLp);

        console.log("\n=== Deployer Test Balances ===");
        console.log("MYR  :", myr.balanceOf(deployer));
        console.log("SGD  :", sgd.balanceOf(deployer));
        console.log("IDRX :", idrx.balanceOf(deployer));
        console.log("USDT :", usdt.balanceOf(deployer));

        vm.stopBroadcast();

        _printSummary(
            address(engine),
            address(myr),    address(sgd),    address(idrx),    address(usdt),
            address(myrPool),address(sgdPool),address(idrxPool),address(usdtPool),
            address(myrFeed),address(sgdFeed),address(idrxFeed),address(usdtFeed)
        );
    }

    function _printSummary(
        address engine,
        address myr,    address sgd,    address idrx,    address usdt,
        address myrPool,address sgdPool,address idrxPool,address usdtPool,
        address myrFeed,address sgdFeed,address idrxFeed,address usdtFeed
    ) internal pure {
        console.log("\n=================================================");
        console.log(  "                DEPLOYMENT SUMMARY               ");
        console.log(  "=================================================");
        console.log(  "FXEngine   :", engine);
        console.log(  "-------------------------------------------------");
        console.log(  "Tokens");
        console.log(  "  MYR  :", myr);
        console.log(  "  SGD  :", sgd);
        console.log(  "  IDRX :", idrx);
        console.log(  "  USDT :", usdt);
        console.log(  "-------------------------------------------------");
        console.log(  "Pools");
        console.log(  "  wMYR  pool :", myrPool);
        console.log(  "  wSGD  pool :", sgdPool);
        console.log(  "  wIDRX pool :", idrxPool);
        console.log(  "  wUSDT pool :", usdtPool);
        console.log(  "-------------------------------------------------");
        console.log(  "Price Feeds (mock, 8 dec USD)");
        console.log(  "  MYR  feed :", myrFeed);
        console.log(  "  SGD  feed :", sgdFeed);
        console.log(  "  IDRX feed :", idrxFeed);
        console.log(  "  USDT feed :", usdtFeed);
        console.log(  "=================================================");
    }
}
