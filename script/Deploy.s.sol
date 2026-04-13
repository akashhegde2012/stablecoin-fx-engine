// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

import "../src/oracles/OracleAggregator.sol";
import "../src/pools/FXPool.sol";
import "../src/FXEngine.sol";

/// @title Deploy
/// @notice Deployment script for Kaia Kairos testnet with dual-oracle support.
contract Deploy is Script {
    // ── Orakl Network aggregator proxies (Kairos, TOKEN/USD, 8-dec) ────────────
    address constant MYR_ORAKL_FEED  = 0x52B73aD55d8BAAFA0f7769934bAFfb5A0Ebb02B3;
    address constant SGD_ORAKL_FEED  = 0x3c6D320f3b3ff80f6c8B78c1146EDb05f888aaB3;
    address constant IDR_ORAKL_FEED  = 0x0b5a141Fcc3d124e078FFa73c1Fc3d408fCfE306;
    address constant USDT_ORAKL_FEED = 0x2D9A3d17400332c44ff0E2dC1b728529a33F5591;

    // ── Pyth Network (Kairos testnet) ──────────────────────────────────────────
    address constant PYTH_CONTRACT   = 0x2880aB155794e7179c9eE2e38200202908C17B43;

    // Pyth price feed IDs (bytes32)
    // NOTE: FX feeds are quoted as USD/TOKEN (inverted vs Orakl's TOKEN/USD).
    bytes32 constant PYTH_USD_MYR_ID = 0x6049eac22964b1ac2119e54c98f3caa165817d84273a121ee122fafb664a8094; // FX.USD/MYR
    bytes32 constant PYTH_USD_SGD_ID = 0x396a969a9c1480fa15ed50bc59149e2c0075a72fe8f458ed941ddec48bdb4918; // FX.USD/SGD
    bytes32 constant PYTH_USD_IDR_ID = 0x6693afcd49878bbd622e46bd805e7177932cf6ab0b1c91b135d71151b9207433; // FX.USD/IDR
    bytes32 constant PYTH_USDT_USD_ID = 0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b; // Crypto.USDT/USD

    // FX feeds need inversion (USD/TOKEN → TOKEN/USD), crypto feeds do not.
    bool constant FX_NEEDS_INVERT    = true;
    bool constant CRYPTO_NO_INVERT   = false;

    // ── Pool parameters ────────────────────────────────────────────────────────
    uint256 constant MYR_SEED   =      390_000 ether;
    uint256 constant SGD_SEED   =      126_500 ether;
    uint256 constant IDRX_SEED  = 1_677_850_000 ether;
    uint256 constant USDT_SEED  =      100_000 ether;

    uint256 constant TEST_MYR   =       50_000 ether;
    uint256 constant TEST_SGD   =       15_000 ether;
    uint256 constant TEST_IDRX  =  167_785_000 ether;
    uint256 constant TEST_USDT  =       10_000 ether;

    uint256 constant FEE_RATE = 30; // 0.30 % bps
    uint256 constant DEVIATION_BPS = 300; // 3 % max deviation between oracles

    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. Deploy stablecoin tokens
        MYRToken  myr  = new MYRToken(deployer);
        SGDToken  sgd  = new SGDToken(deployer);
        IDRXToken idrx = new IDRXToken(deployer);
        USDTToken usdt = new USDTToken(deployer);

        console.log("=== Stablecoin Tokens ===");
        console.log("MYR  :", address(myr));
        console.log("SGD  :", address(sgd));
        console.log("IDRX :", address(idrx));
        console.log("USDT :", address(usdt));

        // 2. Deploy Oracle Aggregators (one per pool)
        OracleAggregator myrOracle  = new OracleAggregator(
            MYR_ORAKL_FEED, PYTH_CONTRACT, PYTH_USD_MYR_ID, FX_NEEDS_INVERT, DEVIATION_BPS, deployer
        );
        OracleAggregator sgdOracle  = new OracleAggregator(
            SGD_ORAKL_FEED, PYTH_CONTRACT, PYTH_USD_SGD_ID, FX_NEEDS_INVERT, DEVIATION_BPS, deployer
        );
        OracleAggregator idrxOracle = new OracleAggregator(
            IDR_ORAKL_FEED, PYTH_CONTRACT, PYTH_USD_IDR_ID, FX_NEEDS_INVERT, DEVIATION_BPS, deployer
        );
        OracleAggregator usdtOracle = new OracleAggregator(
            USDT_ORAKL_FEED, PYTH_CONTRACT, PYTH_USDT_USD_ID, CRYPTO_NO_INVERT, DEVIATION_BPS, deployer
        );

        console.log("\n=== Oracle Aggregators ===");
        console.log("MYR  oracle:", address(myrOracle));
        console.log("SGD  oracle:", address(sgdOracle));
        console.log("IDRX oracle:", address(idrxOracle));
        console.log("USDT oracle:", address(usdtOracle));

        // 3. Deploy FX pools (using oracle aggregators)
        FXPool myrPool  = new FXPool(address(myr),  address(myrOracle),  "Wrapped MYR",  "wMYR",  FEE_RATE, deployer);
        FXPool sgdPool  = new FXPool(address(sgd),  address(sgdOracle),  "Wrapped SGD",  "wSGD",  FEE_RATE, deployer);
        FXPool idrxPool = new FXPool(address(idrx), address(idrxOracle), "Wrapped IDRX", "wIDRX", FEE_RATE, deployer);
        FXPool usdtPool = new FXPool(address(usdt), address(usdtOracle), "Wrapped USDT", "wUSDT", FEE_RATE, deployer);

        console.log("\n=== FX Pools ===");
        console.log("MYR  pool:", address(myrPool),  " lpToken:", myrPool.lpToken());
        console.log("SGD  pool:", address(sgdPool),  " lpToken:", sgdPool.lpToken());
        console.log("IDRX pool:", address(idrxPool), " lpToken:", idrxPool.lpToken());
        console.log("USDT pool:", address(usdtPool), " lpToken:", usdtPool.lpToken());

        // 4. Deploy FX Engine and register pools
        FXEngine engine = new FXEngine(deployer, PYTH_CONTRACT);
        engine.registerPool(address(myr),  address(myrPool));
        engine.registerPool(address(sgd),  address(sgdPool));
        engine.registerPool(address(idrx), address(idrxPool));
        engine.registerPool(address(usdt), address(usdtPool));

        console.log("\n=== FX Engine ===");
        console.log("FXEngine:", address(engine));

        // 5. Authorise engine in every pool
        myrPool.setFXEngine(address(engine));
        sgdPool.setFXEngine(address(engine));
        idrxPool.setFXEngine(address(engine));
        usdtPool.setFXEngine(address(engine));

        // 6. Mint tokens (pool seed + tester allocation)
        myr.mint(deployer,  MYR_SEED  + TEST_MYR);
        sgd.mint(deployer,  SGD_SEED  + TEST_SGD);
        idrx.mint(deployer, IDRX_SEED + TEST_IDRX);
        usdt.mint(deployer, USDT_SEED + TEST_USDT);

        // 7. Approve and seed initial liquidity
        myr.approve(address(myrPool),   MYR_SEED);
        sgd.approve(address(sgdPool),   SGD_SEED);
        idrx.approve(address(idrxPool), IDRX_SEED);
        usdt.approve(address(usdtPool), USDT_SEED);

        uint256 myrLp  = myrPool.deposit(MYR_SEED);
        uint256 sgdLp  = sgdPool.deposit(SGD_SEED);
        uint256 idrxLp = idrxPool.deposit(IDRX_SEED);
        uint256 usdtLp = usdtPool.deposit(USDT_SEED);

        console.log("\n=== Initial Liquidity Seeded ===");
        console.log("MYR  pool balance:", myrPool.getPoolBalance(),  " wMYR  minted:", myrLp);
        console.log("SGD  pool balance:", sgdPool.getPoolBalance(),  " wSGD  minted:", sgdLp);
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
            address(myr),    address(sgd),    address(idrx),    address(usdt),
            address(myrOracle), address(sgdOracle), address(idrxOracle), address(usdtOracle),
            address(myrPool),address(sgdPool),address(idrxPool),address(usdtPool)
        );
    }

    function _printSummary(
        address engine,
        address myr,    address sgd,    address idrx,    address usdt,
        address myrOracle, address sgdOracle, address idrxOracle, address usdtOracle,
        address myrPool,address sgdPool,address idrxPool,address usdtPool
    ) internal pure {
        console.log("\n=================================================");
        console.log(  "       DEPLOYMENT SUMMARY (KAIROS - DUAL ORACLE) ");
        console.log(  "=================================================");
        console.log(  "FXEngine   :", engine);
        console.log(  "-------------------------------------------------");
        console.log(  "Tokens");
        console.log(  "  MYR  :", myr);
        console.log(  "  SGD  :", sgd);
        console.log(  "  IDRX :", idrx);
        console.log(  "  USDT :", usdt);
        console.log(  "-------------------------------------------------");
        console.log(  "Oracle Aggregators (Orakl primary + Pyth fallback)");
        console.log(  "  MYR  oracle :", myrOracle);
        console.log(  "  SGD  oracle :", sgdOracle);
        console.log(  "  IDRX oracle :", idrxOracle);
        console.log(  "  USDT oracle :", usdtOracle);
        console.log(  "-------------------------------------------------");
        console.log(  "Pools");
        console.log(  "  wMYR  pool :", myrPool);
        console.log(  "  wSGD  pool :", sgdPool);
        console.log(  "  wIDRX pool :", idrxPool);
        console.log(  "  wUSDT pool :", usdtPool);
        console.log(  "-------------------------------------------------");
        console.log(  "Oracles");
        console.log(  "  Orakl (primary, push)");
        console.log(  "    MYR-USD  : 0x52B73aD55d8BAAFA0f7769934bAFfb5A0Ebb02B3");
        console.log(  "    SGD-USD  : 0x3c6D320f3b3ff80f6c8B78c1146EDb05f888aaB3");
        console.log(  "    IDR-USD  : 0x0b5a141Fcc3d124e078FFa73c1Fc3d408fCfE306");
        console.log(  "    USDT-USD : 0x2D9A3d17400332c44ff0E2dC1b728529a33F5591");
        console.log(  "  Pyth (fallback, pull)");
        console.log(  "    Contract : 0x2880ab155794e7179c9ee2e38200202908c17b43");
        console.log(  "    USD/MYR  : 6049eac2...a8094 (inverted)");
        console.log(  "    USD/SGD  : 396a969a...b4918 (inverted)");
        console.log(  "    USD/IDR  : 6693afcd...07433 (inverted)");
        console.log(  "    USDT/USD : 2b89b9dc...e53b  (direct)");
        console.log(  "=================================================");
    }
}
