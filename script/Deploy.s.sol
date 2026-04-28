// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

import "../src/pools/FXPool.sol";
import "../src/FXEngine.sol";

/// @title Deploy
/// @notice Deployment script for Kaia Kairos testnet.
///
///  Price feeds: Orakl Network aggregator proxies (Kairos, 8-decimal USD feeds)
///
///  Feed          Pair        Proxy address
///  ──────────────────────────────────────────────────────────────────────────
///  MYR-USD       MYR/USD     0x52b73ad55d8baafa0f7769934baffb5a0ebb02b3
///  SGD-USD       SGD/USD     0x3c6d320f3b3ff80f6c8b78c1146edb05f888aab3
///  IDR-USD       IDR/USD     0x0b5a141fcc3d124e078ffa73c1fc3d408fcfe306
///                (IDRX is 1:1 with IDR, IDR-USD is used as the price source)
///  USDT-USD      USDT/USD    0x2d9a3d17400332c44ff0e2dc1b728529a33f5591
///
///  Initial pool liquidity (~$100k each, smaller than mainnet seed):
///
///  Pool     Initial balance
///  ────────────────────────
///  MYR        390 000 MYR
///  SGD        126 500 SGD
///  IDRX   1 677 850 000 IDRX
///  USDT       100 000 USDT
contract Deploy is Script {
    // Orakl Network aggregator proxy addresses on Kairos testnet
    address constant MYR_FEED = 0x52B73aD55d8BAAFA0f7769934bAFfb5A0Ebb02B3;
    address constant SGD_FEED = 0x3c6D320f3b3ff80f6c8B78c1146EDb05f888aaB3;
    address constant IDR_FEED = 0x0b5a141Fcc3d124e078FFa73c1Fc3d408fCfE306; // used for IDRX (1:1 IDR)
    address constant USDT_FEED = 0x2D9A3d17400332c44ff0E2dC1b728529a33F5591;

    // Pool seed liquidity (~$100k each)
    uint256 constant MYR_SEED = 390_000 ether;
    uint256 constant SGD_SEED = 126_500 ether;
    uint256 constant IDRX_SEED = 1_677_850_000 ether;
    uint256 constant USDT_SEED = 100_000 ether;

    // Additional tokens minted to deployer for testing
    uint256 constant TEST_MYR = 50_000 ether;
    uint256 constant TEST_SGD = 15_000 ether;
    uint256 constant TEST_IDRX = 167_785_000 ether;
    uint256 constant TEST_USDT = 10_000 ether;

    uint256 constant FEE_RATE = 30; // 0.30 % bps

    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. Deploy stablecoin tokens
        MYRToken myr = new MYRToken(deployer);
        SGDToken sgd = new SGDToken(deployer);
        IDRXToken idrx = new IDRXToken(deployer);
        USDTToken usdt = new USDTToken(deployer);

        console.log("=== Stablecoin Tokens ===");
        console.log("MYR  :", address(myr));
        console.log("SGD  :", address(sgd));
        console.log("IDRX :", address(idrx));
        console.log("USDT :", address(usdt));

        // 2. Deploy FX pools (using live Orakl feeds — no mocks)
        FXPool myrPool = new FXPool(address(myr), MYR_FEED, "Wrapped MYR", "wMYR", FEE_RATE, deployer);
        FXPool sgdPool = new FXPool(address(sgd), SGD_FEED, "Wrapped SGD", "wSGD", FEE_RATE, deployer);
        FXPool idrxPool = new FXPool(address(idrx), IDR_FEED, "Wrapped IDRX", "wIDRX", FEE_RATE, deployer);
        FXPool usdtPool = new FXPool(address(usdt), USDT_FEED, "Wrapped USDT", "wUSDT", FEE_RATE, deployer);

        console.log("\n=== FX Pools ===");
        console.log("MYR  pool:", address(myrPool), " lpToken:", myrPool.lpToken());
        console.log("SGD  pool:", address(sgdPool), " lpToken:", sgdPool.lpToken());
        console.log("IDRX pool:", address(idrxPool), " lpToken:", idrxPool.lpToken());
        console.log("USDT pool:", address(usdtPool), " lpToken:", usdtPool.lpToken());

        // 3. Deploy FX Engine and register pools
        FXEngine engine = new FXEngine(deployer);
        engine.registerPool(address(myr), address(myrPool));
        engine.registerPool(address(sgd), address(sgdPool));
        engine.registerPool(address(idrx), address(idrxPool));
        engine.registerPool(address(usdt), address(usdtPool));

        console.log("\n=== FX Engine ===");
        console.log("FXEngine:", address(engine));

        // 4. Authorise engine in every pool
        myrPool.proposeEngine(address(engine));
        myrPool.acceptEngine();
        sgdPool.proposeEngine(address(engine));
        sgdPool.acceptEngine();
        idrxPool.proposeEngine(address(engine));
        idrxPool.acceptEngine();
        usdtPool.proposeEngine(address(engine));
        usdtPool.acceptEngine();

        // 5. Mint tokens (pool seed + tester allocation)
        myr.mint(deployer, MYR_SEED + TEST_MYR);
        sgd.mint(deployer, SGD_SEED + TEST_SGD);
        idrx.mint(deployer, IDRX_SEED + TEST_IDRX);
        usdt.mint(deployer, USDT_SEED + TEST_USDT);

        // 6. Approve and seed initial liquidity
        myr.approve(address(myrPool), MYR_SEED);
        sgd.approve(address(sgdPool), SGD_SEED);
        idrx.approve(address(idrxPool), IDRX_SEED);
        usdt.approve(address(usdtPool), USDT_SEED);

        uint256 myrLp = myrPool.deposit(MYR_SEED);
        uint256 sgdLp = sgdPool.deposit(SGD_SEED);
        uint256 idrxLp = idrxPool.deposit(IDRX_SEED);
        uint256 usdtLp = usdtPool.deposit(USDT_SEED);

        console.log("\n=== Initial Liquidity Seeded ===");
        console.log("MYR  pool balance:", myrPool.getPoolBalance(), " wMYR  minted:", myrLp);
        console.log("SGD  pool balance:", sgdPool.getPoolBalance(), " wSGD  minted:", sgdLp);
        console.log("IDRX pool balance:", idrxPool.getPoolBalance(), " wIDRX minted:", idrxLp);
        console.log("USDT pool balance:", usdtPool.getPoolBalance(), " wUSDT minted:", usdtLp);

        console.log("\n=== Deployer Test Balances ===");
        console.log("MYR  :", myr.balanceOf(deployer));
        console.log("SGD  :", sgd.balanceOf(deployer));
        console.log("IDRX :", idrx.balanceOf(deployer));
        console.log("USDT :", usdt.balanceOf(deployer));

        vm.stopBroadcast();

        _printSummary(
            address(engine),
            address(myr),
            address(sgd),
            address(idrx),
            address(usdt),
            address(myrPool),
            address(sgdPool),
            address(idrxPool),
            address(usdtPool)
        );
    }

    function _printSummary(
        address engine,
        address myr,
        address sgd,
        address idrx,
        address usdt,
        address myrPool,
        address sgdPool,
        address idrxPool,
        address usdtPool
    ) internal pure {
        console.log("\n=================================================");
        console.log("              DEPLOYMENT SUMMARY (KAIROS)        ");
        console.log("=================================================");
        console.log("FXEngine   :", engine);
        console.log("-------------------------------------------------");
        console.log("Tokens");
        console.log("  MYR  :", myr);
        console.log("  SGD  :", sgd);
        console.log("  IDRX :", idrx);
        console.log("  USDT :", usdt);
        console.log("-------------------------------------------------");
        console.log("Pools");
        console.log("  wMYR  pool :", myrPool);
        console.log("  wSGD  pool :", sgdPool);
        console.log("  wIDRX pool :", idrxPool);
        console.log("  wUSDT pool :", usdtPool);
        console.log("-------------------------------------------------");
        console.log("Price Feeds (Orakl Network, Kairos testnet)");
        console.log("  MYR-USD  : 0x52B73aD55d8BAAFA0f7769934bAFfb5A0Ebb02B3");
        console.log("  SGD-USD  : 0x3c6D320f3b3ff80f6c8B78c1146EDb05f888aaB3");
        console.log("  IDR-USD  : 0x0b5a141Fcc3d124e078FFa73c1Fc3d408fCfE306");
        console.log("  USDT-USD : 0x2D9A3d17400332c44ff0E2dC1b728529a33F5591");
        console.log("=================================================");
    }
}
