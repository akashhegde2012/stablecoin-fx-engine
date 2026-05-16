// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./mocks/MockOraklFeed.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

import "../src/oracles/OracleAggregator.sol";
import "../src/pools/FXPool.sol";
import "../src/pools/LPToken.sol";
import "../src/FXEngine.sol";

import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

/// @title FXEngineTest
/// @notice Full integration test suite for the FX engine with dual-oracle support.
contract FXEngineTest is Test {
    // ── Price feed constants (8 decimals, USD) ────────────────────────────────
    int256 constant MYR_USD = 22_680_000; // $0.2268
    int256 constant SGD_USD = 74_190_000; // $0.7419
    int256 constant IDRX_USD = 6_170; // $0.0000617
    int256 constant USDT_USD = 100_000_000; // $1.0000

    // Pyth equivalent prices (USD/TOKEN for FX pairs, TOKEN/USD for crypto)
    // Inversion: TOKEN/USD = 10^16 / pyth_price (both at expo=-8)
    // USD/MYR: 10^16 / 22680000 = 440917107
    int64 constant PYTH_USD_MYR  = 440_917_107;
    // USD/SGD: 10^16 / 74190000 = 134815760
    int64 constant PYTH_USD_SGD  = 134_815_760;
    // USD/IDR: USD/IDR = 1/(IDR/USD) = 1/(6170*10^-8) = 10^8/6170 = 16207.46; with expo=-8 → 16207.46*10^8 = 1620745600000
    int64 constant PYTH_USD_IDR  = 1_620_745_600_000;
    // USDT/USD = 1.0
    int64 constant PYTH_USDT_USD = 100_000_000;

    int32 constant FX_EXPO   = -8; // Use -8 for all to match Orakl's 8-decimal format
    int32 constant CRYPTO_EXPO = -8;

    uint256 constant BASE_FEE_RATE = 10;       // 0.10% base fee (bps)
    uint256 constant UTILIZATION_FACTOR = 2000; // scaling factor (bps)
    uint256 constant MAX_DYNAMIC_FEE = 300;     // 3.00% cap (bps)
    uint256 constant PLATFORM_FEE_BPS = 3000;   // 30% of total fees to platform
    uint256 constant DEVIATION_BPS = 300;       // 3 %

    // ── Actors ─────────────────────────────────────────────────────────────────
    address owner = makeAddr("owner");
    address alice    = makeAddr("alice");    // LP provider
    address bob      = makeAddr("bob");      // trader
    address treasury = makeAddr("treasury");

    // ── Tokens ─────────────────────────────────────────────────────────────────
    MYRToken myr;
    SGDToken sgd;
    IDRXToken idrx;
    USDTToken usdt;

    // ── Mock feeds (Orakl v0.2 interface) ────────────────────────────────────
    MockOraklFeed myrOraklFeed;
    MockOraklFeed sgdOraklFeed;
    MockOraklFeed idrxOraklFeed;
    MockOraklFeed usdtOraklFeed;

    // ── Mock Pyth ──────────────────────────────────────────────────────────────
    MockPyth pyth;

    // Pyth price feed IDs (dummy for testing)
    bytes32 constant PYTH_MYR_ID  = bytes32(uint256(1));
    bytes32 constant PYTH_SGD_ID  = bytes32(uint256(2));
    bytes32 constant PYTH_IDR_ID  = bytes32(uint256(3));
    bytes32 constant PYTH_USDT_ID = bytes32(uint256(4));

    // ── Oracle Aggregators ─────────────────────────────────────────────────────
    OracleAggregator myrOracle;
    OracleAggregator sgdOracle;
    OracleAggregator idrxOracle;
    OracleAggregator usdtOracle;

    // ── Pools & engine ─────────────────────────────────────────────────────────
    FXPool myrPool;
    FXPool sgdPool;
    FXPool idrxPool;
    FXPool usdtPool;
    FXEngine engine;

    // ── Seed amounts ──────────────────────────────────────────────────────────
    uint256 constant MYR_SEED = 1_000_000 ether;
    uint256 constant SGD_SEED = 305_662 ether; // ≈ same USD value as 1M MYR
    uint256 constant IDRX_SEED = 3_677_472_000 ether; // ≈ same USD value
    uint256 constant USDT_SEED = 226_800 ether; // ≈ same USD value

    // ─────────────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(owner);

        // Tokens
        myr = new MYRToken(owner);
        sgd = new SGDToken(owner);
        idrx = new IDRXToken(owner);
        usdt = new USDTToken(owner);

        // Mock Orakl feeds
        myrOraklFeed  = new MockOraklFeed(8, MYR_USD);
        sgdOraklFeed  = new MockOraklFeed(8, SGD_USD);
        idrxOraklFeed = new MockOraklFeed(8, IDRX_USD);
        usdtOraklFeed = new MockOraklFeed(8, USDT_USD);

        // Mock Pyth
        pyth = new MockPyth(60, 0); // 60s valid time, 0 fee

        // Seed Pyth prices
        _seedPythPrice(PYTH_MYR_ID,  PYTH_USD_MYR,  FX_EXPO);
        _seedPythPrice(PYTH_SGD_ID,  PYTH_USD_SGD,  FX_EXPO);
        _seedPythPrice(PYTH_IDR_ID,  PYTH_USD_IDR,  FX_EXPO);
        _seedPythPrice(PYTH_USDT_ID, PYTH_USDT_USD, CRYPTO_EXPO);

        // Oracle Aggregators
        myrOracle  = new OracleAggregator(
            address(myrOraklFeed), address(pyth), PYTH_MYR_ID, true, DEVIATION_BPS, owner
        );
        sgdOracle  = new OracleAggregator(
            address(sgdOraklFeed), address(pyth), PYTH_SGD_ID, true, DEVIATION_BPS, owner
        );
        idrxOracle = new OracleAggregator(
            address(idrxOraklFeed), address(pyth), PYTH_IDR_ID, true, DEVIATION_BPS, owner
        );
        usdtOracle = new OracleAggregator(
            address(usdtOraklFeed), address(pyth), PYTH_USDT_ID, false, DEVIATION_BPS, owner
        );

        // Pools with oracle aggregator + dynamic fee + platform fee params
        myrPool  = new FXPool(address(myr),  address(myrOracle),  "Wrapped MYR",  "wMYR",  BASE_FEE_RATE, UTILIZATION_FACTOR, MAX_DYNAMIC_FEE, PLATFORM_FEE_BPS, treasury, owner);
        sgdPool  = new FXPool(address(sgd),  address(sgdOracle),  "Wrapped SGD",  "wSGD",  BASE_FEE_RATE, UTILIZATION_FACTOR, MAX_DYNAMIC_FEE, PLATFORM_FEE_BPS, treasury, owner);
        idrxPool = new FXPool(address(idrx), address(idrxOracle), "Wrapped IDRX", "wIDRX", BASE_FEE_RATE, UTILIZATION_FACTOR, MAX_DYNAMIC_FEE, PLATFORM_FEE_BPS, treasury, owner);
        usdtPool = new FXPool(address(usdt), address(usdtOracle), "Wrapped USDT", "wUSDT", BASE_FEE_RATE, UTILIZATION_FACTOR, MAX_DYNAMIC_FEE, PLATFORM_FEE_BPS, treasury, owner);

        // Engine
        engine = new FXEngine(owner, address(pyth));
        engine.registerPool(address(myr),  address(myrPool));
        engine.registerPool(address(sgd),  address(sgdPool));
        engine.registerPool(address(idrx), address(idrxPool));
        engine.registerPool(address(usdt), address(usdtPool));

        // Authorise engine in pools
        myrPool.proposeEngine(address(engine));
        myrPool.acceptEngine();
        sgdPool.proposeEngine(address(engine));
        sgdPool.acceptEngine();
        idrxPool.proposeEngine(address(engine));
        idrxPool.acceptEngine();
        usdtPool.proposeEngine(address(engine));
        usdtPool.acceptEngine();

        // Mint to alice (LP) and bob (trader)
        myr.mint(alice, MYR_SEED + 10_000 ether);
        sgd.mint(alice, SGD_SEED + 10_000 ether);
        idrx.mint(alice, IDRX_SEED + 1_000_000_000 ether);
        usdt.mint(alice, USDT_SEED + 10_000 ether);

        myr.mint(bob, 100_000 ether);
        sgd.mint(bob, 100_000 ether);
        usdt.mint(bob, 10_000 ether);

        vm.stopPrank();

        // Alice provides initial liquidity
        vm.startPrank(alice);
        myr.approve(address(myrPool), MYR_SEED);
        sgd.approve(address(sgdPool), SGD_SEED);
        idrx.approve(address(idrxPool), IDRX_SEED);
        usdt.approve(address(usdtPool), USDT_SEED);

        myrPool.deposit(MYR_SEED);
        sgdPool.deposit(SGD_SEED);
        idrxPool.deposit(IDRX_SEED);
        usdtPool.deposit(USDT_SEED);
        vm.stopPrank();
    }

    // ── Helper: seed a Pyth price via MockPyth ─────────────────────────────────
    function _seedPythPrice(bytes32 id, int64 price, int32 expo) internal {
        bytes memory data = pyth.createPriceFeedUpdateData(
            id, price, 1000, expo, price, 1000, uint64(block.timestamp)
        );
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = data;
        pyth.updatePriceFeeds{value: 0}(updateData);
    }

    // =========================================================================
    // Deployment sanity
    // =========================================================================

    function test_PoolsSeeded() public view {
        assertEq(myrPool.getPoolBalance(), MYR_SEED);
        assertEq(sgdPool.getPoolBalance(), SGD_SEED);
        assertEq(idrxPool.getPoolBalance(), IDRX_SEED);
        assertEq(usdtPool.getPoolBalance(), USDT_SEED);
    }

    function test_LPTokensMinted() public view {
        LPToken wMYR = LPToken(myrPool.lpToken());
        assertEq(wMYR.balanceOf(alice), MYR_SEED - 1000);
    }

    function test_EnginePoolsRegistered() public view {
        assertEq(address(engine.pools(address(myr))), address(myrPool));
        assertEq(address(engine.pools(address(sgd))), address(sgdPool));
        assertEq(address(engine.pools(address(idrx))), address(idrxPool));
        assertEq(address(engine.pools(address(usdt))), address(usdtPool));
        assertEq(engine.getRegisteredTokens().length, 4);
    }

    function test_StablecoinToken_MintBurnDecimalsAndOwner() public {
        assertEq(myr.decimals(), 18);

        vm.prank(owner);
        myr.mint(bob, 123 ether);
        assertEq(myr.balanceOf(bob), 100_123 ether);

        vm.prank(bob);
        myr.burn(23 ether);
        assertEq(myr.balanceOf(bob), 100_100 ether);

        vm.prank(bob);
        vm.expectRevert();
        myr.mint(bob, 1 ether);
    }

    function test_FXEngine_AdminAndPoolRegistryBranches() public {
        address newPyth = makeAddr("newPyth");

        vm.prank(owner);
        engine.setPyth(newPyth);
        assertEq(address(engine.pyth()), newPyth);

        vm.prank(owner);
        vm.expectRevert("FXEngine: zero token");
        engine.registerPool(address(0), address(myrPool));

        vm.prank(owner);
        vm.expectRevert("FXEngine: zero pool");
        engine.registerPool(makeAddr("newToken"), address(0));

        uint256 tokenCount = engine.getRegisteredTokens().length;
        vm.prank(owner);
        engine.registerPool(address(myr), address(myrPool));
        assertEq(engine.getRegisteredTokens().length, tokenCount);

        vm.prank(owner);
        vm.expectRevert("FXEngine: pool not found");
        engine.removePool(makeAddr("missingToken"));

        vm.prank(owner);
        vm.expectRevert("FXEngine: no pool");
        engine.getPoolInfo(makeAddr("missingToken"));
    }

    function test_FXPool_ConstructorBounds() public {
        vm.startPrank(owner);
        vm.expectRevert("FXPool: zero stablecoin");
        new FXPool(
            address(0),
            address(myrOracle),
            "Bad",
            "BAD",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: zero oracle");
        new FXPool(
            address(myr),
            address(0),
            "Bad",
            "BAD",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: base fee too high");
        new FXPool(
            address(myr),
            address(myrOracle),
            "Bad",
            "BAD",
            1_001,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: max fee too high");
        new FXPool(
            address(myr),
            address(myrOracle),
            "Bad",
            "BAD",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            1_001,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: base > max");
        new FXPool(
            address(myr),
            address(myrOracle),
            "Bad",
            "BAD",
            20,
            UTILIZATION_FACTOR,
            10,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: platform bps too high");
        new FXPool(
            address(myr),
            address(myrOracle),
            "Bad",
            "BAD",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            10_001,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: zero treasury");
        new FXPool(
            address(myr),
            address(myrOracle),
            "Bad",
            "BAD",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            PLATFORM_FEE_BPS,
            address(0),
            owner
        );
        vm.stopPrank();
    }

    function test_OracleAggregator_ConstructorBounds() public {
        vm.startPrank(owner);
        vm.expectRevert("OA: zero orakl");
        new OracleAggregator(address(0), address(pyth), PYTH_MYR_ID, true, DEVIATION_BPS, owner);

        vm.expectRevert("OA: zero pyth");
        new OracleAggregator(address(myrOraklFeed), address(0), PYTH_MYR_ID, true, DEVIATION_BPS, owner);
        vm.stopPrank();
    }

    // =========================================================================
    // Oracle Aggregator
    // =========================================================================

    function test_GetPrice_MYR() public view {
        (int256 price, uint8 dec) = myrPool.getPrice();
        // Price should be close to Orakl's value (within 3% deviation)
        assertApproxEqAbs(uint256(price), uint256(MYR_USD), uint256(MYR_USD) / 33);
        assertEq(dec, 8);
    }

    function test_GetPrice_IDRX() public view {
        (int256 price,) = idrxPool.getPrice();
        assertApproxEqAbs(uint256(price), uint256(IDRX_USD), uint256(IDRX_USD) / 33);
    }

    function test_OracleAggregator_OraklFallback() public {
        // Corrupt Pyth price to be way off — aggregator should still use Orakl
        // (cross-validation would revert, but Orakl alone should work if we disable cross-val)
        vm.prank(owner);
        myrOracle.setCrossValidation(false);

        (int256 price, uint8 dec) = myrPool.getPrice();
        assertEq(price, MYR_USD);
        assertEq(dec, 8);
    }

    function test_OracleAggregator_PythFallback() public {
        // Break Orakl by setting answer to 0 (invalid)
        myrOraklFeed.updateAnswer(0);

        // Disable cross-validation so it falls back to Pyth alone
        vm.prank(owner);
        myrOracle.setCrossValidation(false);

        // Now getPrice should use Pyth (inverted USD/MYR -> MYR/USD)
        (int256 price,) = myrPool.getPrice();
        // Inverted: 10^16 / PYTH_USD_MYR = 10^16 / 4_409_171_00
        // Should be close to the Orakl price
        assertApproxEqAbs(uint256(price), uint256(MYR_USD), uint256(MYR_USD) / 10); // ~10% tolerance for inversion rounding
    }

    function test_OracleAggregator_BothDown_Reverts() public {
        // Break Orakl
        myrOraklFeed.updateAnswer(0);

        vm.prank(owner);
        myrOracle.setCrossValidation(false);

        // Warp time so Pyth price becomes stale (older than 120s)
        vm.warp(block.timestamp + 200);

        vm.expectRevert("OA: both oracles down");
        myrPool.getPrice();
    }

    function test_OracleAggregator_CrossValidationDeviationReverts() public {
        myrOraklFeed.updateAnswer(MYR_USD * 2);

        vm.expectRevert("OA: price deviation too high");
        myrPool.getPrice();
    }

    function test_OracleAggregator_AdminSettersAndBounds() public {
        vm.startPrank(owner);
        myrOracle.setDeviationThreshold(500);
        assertEq(myrOracle.deviationThresholdBps(), 500);

        vm.expectRevert("OA: threshold too high");
        myrOracle.setDeviationThreshold(501);

        myrOracle.setCrossValidation(false);
        assertFalse(myrOracle.crossValidationEnabled());

        myrOracle.setMaxStaleness(999);
        assertEq(myrOracle.maxStaleness(), 999);
        vm.stopPrank();
    }

    function test_OracleAggregator_DirectPythPriceAndInvert() public view {
        (int256 pythPrice, uint8 dec) = myrOracle.getPythPrice();
        assertApproxEqAbs(uint256(pythPrice), uint256(MYR_USD), uint256(MYR_USD) / 10);
        assertEq(dec, 8);
    }

    // =========================================================================
    // Quote calculation
    // =========================================================================

    function test_GetQuote_MYRtoSGD() public view {
        uint256 amountIn = 100 ether;
        uint256 quote = engine.getQuote(address(myr), address(sgd), amountIn);

        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 effectiveRate = sgdPool.getEffectiveFeeRate(grossOut);
        uint256 fee = (grossOut * effectiveRate) / 10_000;
        uint256 expected = grossOut - fee;

        assertEq(quote, expected);
        // With low utilization (100 MYR vs 305k SGD pool), fee is near base
        assertGt(quote, 30 ether);
        assertLt(quote, 31 ether);
    }

    function test_GetQuote_USDTtoIDRX() public view {
        uint256 amountIn = 100 ether;
        uint256 quote = engine.getQuote(address(usdt), address(idrx), amountIn);

        uint256 grossOut = (amountIn * uint256(USDT_USD)) / uint256(IDRX_USD);
        uint256 effectiveRate = idrxPool.getEffectiveFeeRate(grossOut);
        uint256 fee = (grossOut * effectiveRate) / 10_000;
        uint256 expected = grossOut - fee;

        assertEq(quote, expected);
        assertGt(quote, 1_600_000 ether);
        assertLt(quote, 1_700_000 ether);
    }

    function test_GetQuote_IDRXtoUSDT() public view {
        uint256 amountIn = 1_000_000 ether;
        uint256 quote = engine.getQuote(address(idrx), address(usdt), amountIn);

        assertGt(quote, 60 ether);
        assertLt(quote, 63 ether);
    }

    // =========================================================================
    // Swap execution
    // =========================================================================

    function test_Swap_MYRtoSGD() public {
        uint256 amountIn = 1_000 ether;

        uint256 expectedOut = engine.getQuote(address(myr), address(sgd), amountIn);

        uint256 sgdBefore = sgd.balanceOf(bob);
        uint256 myrBefore = myr.balanceOf(bob);

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 actualOut = engine.swap(address(myr), address(sgd), amountIn, expectedOut, bob);
        vm.stopPrank();

        assertEq(actualOut, expectedOut);
        assertEq(myr.balanceOf(bob), myrBefore - amountIn);
        assertEq(sgd.balanceOf(bob), sgdBefore + actualOut);

        assertEq(myrPool.getPoolBalance(), MYR_SEED + amountIn);
        // Pool lost actualOut + platformFee (LP fee stays in pool)
        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 effectiveRate = sgdPool.getEffectiveFeeRate(grossOut);
        uint256 totalFee = (grossOut * effectiveRate) / 10_000;
        uint256 platformFee = (totalFee * PLATFORM_FEE_BPS) / 10_000;
        assertEq(sgdPool.getPoolBalance(), SGD_SEED - actualOut - platformFee);
    }

    function test_Swap_SGDtoMYR() public {
        uint256 amountIn = 305 ether;

        vm.startPrank(bob);
        sgd.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(sgd), address(myr), amountIn, 0, bob);
        vm.stopPrank();

        assertGt(out, 950 ether);
        assertLt(out, 1100 ether);
    }

    function test_Swap_USDTtoIDRX() public {
        uint256 amountIn = 10 ether;

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(idrx), amountIn, 0, bob);
        vm.stopPrank();

        assertGt(out, 160_000 ether);
        assertLt(out, 170_000 ether);
    }

    function test_Swap_USDTtoSGD() public {
        uint256 amountIn = 1_000 ether;

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        assertGt(out, 1_300 ether);
        assertLt(out, 1_400 ether);
    }

    // ── Slippage guard ────────────────────────────────────────────────────────
    function test_Swap_RevertOnSlippage() public {
        uint256 amountIn = 100 ether;
        uint256 tooHighMin = 999_999 ether;

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        vm.expectRevert("FXEngine: slippage exceeded");
        engine.swap(address(myr), address(sgd), amountIn, tooHighMin, bob);
        vm.stopPrank();
    }

    // ── Insufficient liquidity ────────────────────────────────────────────────
    function test_Swap_RevertOnInsufficientLiquidity() public {
        uint256 hugeAmount = 100_000_000 ether;

        vm.prank(owner);
        myr.mint(bob, hugeAmount);

        vm.startPrank(bob);
        myr.approve(address(engine), hugeAmount);
        vm.expectRevert("FXEngine: insufficient output liquidity");
        engine.swap(address(myr), address(sgd), hugeAmount, 0, bob);
        vm.stopPrank();
    }

    // =========================================================================
    // LP deposit / withdraw
    // =========================================================================

    function test_LP_DepositAndWithdraw_Proportional() public {
        address lp2 = makeAddr("lp2");

        vm.prank(owner);
        myr.mint(lp2, 500_000 ether);

        vm.startPrank(lp2);
        myr.approve(address(myrPool), 500_000 ether);
        uint256 lpMinted = myrPool.deposit(500_000 ether);
        vm.stopPrank();

        LPToken wMYR = LPToken(myrPool.lpToken());
        assertEq(lpMinted, 500_000 ether);
        assertEq(wMYR.balanceOf(lp2), 500_000 ether);

        assertEq(myrPool.getPoolBalance(), 1_500_000 ether);
        assertEq(wMYR.totalSupply(), 1_500_000 ether);

        vm.startPrank(lp2);
        uint256 returned = myrPool.withdraw(lpMinted);
        vm.stopPrank();

        assertEq(returned, 500_000 ether);
        assertEq(myr.balanceOf(lp2), 500_000 ether);
    }

    function test_LP_FeeAccruesToOutPool() public {
        FXPool sgdP = sgdPool;
        LPToken wSGD = LPToken(sgdP.lpToken());

        uint256 supplyBefore = wSGD.totalSupply();
        uint256 balanceBefore = sgdP.getPoolBalance();

        uint256 amountIn = 1_000 ether;
        vm.prank(owner);
        myr.mint(bob, amountIn);

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 netOut = engine.swap(address(myr), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 effectiveRate = sgdP.getEffectiveFeeRate(grossOut);
        uint256 fee = (grossOut * effectiveRate) / 10_000;
        uint256 platformFee = (fee * PLATFORM_FEE_BPS) / 10_000;

        uint256 balanceAfter = sgdP.getPoolBalance();
        assertEq(balanceAfter, balanceBefore - netOut - platformFee);
        assertEq(wSGD.totalSupply(), supplyBefore);

        uint256 rateBefore = (balanceBefore * 1e18) / supplyBefore;
        uint256 rateAfter = (balanceAfter * 1e18) / wSGD.totalSupply();

        assertLt(rateAfter, rateBefore);
        assertEq(balanceBefore - balanceAfter, netOut + platformFee);
        assertEq(grossOut - netOut, fee);
        assertGt(fee, 0);

        console.log("Fee earned by sgdPool LPs:", fee);
        console.log("Effective fee rate (bps):", effectiveRate);
        console.log("wSGD rate before (e18):", rateBefore);
        console.log("wSGD rate after  (e18):", rateAfter);
    }

    // =========================================================================
    // Pool admin
    // =========================================================================

    function test_SetBaseFeeRate() public {
        vm.prank(owner);
        myrPool.setBaseFeeRate(20);
        assertEq(myrPool.feeRate(), 20);
    }

    function test_SetBaseFeeRate_RevertOverMax() public {
        vm.prank(owner);
        vm.expectRevert("FXPool: base > max");
        myrPool.setBaseFeeRate(301); // > maxDynamicFeeRate
    }

    function test_SetUtilizationFactor() public {
        vm.prank(owner);
        myrPool.setUtilizationFactor(3000);
        assertEq(myrPool.utilizationFactor(), 3000);
    }

    function test_SetMaxDynamicFeeRate() public {
        vm.prank(owner);
        myrPool.setMaxDynamicFeeRate(500);
        assertEq(myrPool.maxDynamicFeeRate(), 500);
    }

    function test_SetMaxDynamicFeeRate_RevertTooHighAndBelowBase() public {
        vm.prank(owner);
        vm.expectRevert("FXPool: max fee too high");
        myrPool.setMaxDynamicFeeRate(1_001);

        vm.prank(owner);
        myrPool.setBaseFeeRate(200);

        vm.prank(owner);
        vm.expectRevert("FXPool: base > new max");
        myrPool.setMaxDynamicFeeRate(199);
    }

    function test_PlatformFee_SettersBounds() public {
        vm.startPrank(owner);
        vm.expectRevert("FXPool: platform bps too high");
        sgdPool.setPlatformFeeBps(10_001);

        vm.expectRevert("FXPool: zero treasury");
        sgdPool.setPlatformTreasury(address(0));
        vm.stopPrank();
    }

    function test_EngineTwoStepSetter_BoundsAndSuccess() public {
        vm.startPrank(owner);
        FXPool freshPool = new FXPool(
            address(myr),
            address(myrOracle),
            "Fresh MYR",
            "fwMYR",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );

        vm.expectRevert("FXPool: no pending engine");
        freshPool.acceptEngine();

        vm.expectRevert("FXPool: zero engine");
        freshPool.proposeEngine(address(0));

        freshPool.proposeEngine(address(engine));
        assertEq(freshPool.pendingFxEngine(), address(engine));
        freshPool.acceptEngine();
        assertEq(freshPool.fxEngine(), address(engine));
        assertEq(freshPool.pendingFxEngine(), address(0));
        vm.stopPrank();
    }

    function test_RemovePool() public {
        vm.prank(owner);
        engine.removePool(address(myr));
        assertEq(address(engine.pools(address(myr))), address(0));
        assertEq(engine.getRegisteredTokens().length, 3);
    }

    // =========================================================================
    // Security / access control
    // =========================================================================

    function test_Release_RevertFromNonEngine() public {
        vm.prank(alice);
        vm.expectRevert("FXPool: only engine");
        myrPool.release(1 ether, alice);
    }

    function test_FXPool_PauseBlocksDepositWithdrawAndRelease() public {
        vm.prank(owner);
        myrPool.pause();

        vm.startPrank(alice);
        myr.approve(address(myrPool), 1 ether);
        vm.expectRevert();
        myrPool.deposit(1 ether);

        vm.expectRevert();
        myrPool.withdraw(1 ether);
        vm.stopPrank();

        vm.prank(address(engine));
        vm.expectRevert();
        myrPool.release(1 ether, bob);

        vm.prank(owner);
        myrPool.unpause();

        vm.prank(address(engine));
        myrPool.release(1 ether, bob);
    }

    function test_FXPool_ReleaseBounds() public {
        vm.prank(address(engine));
        vm.expectRevert("FXPool: zero recipient");
        myrPool.release(1 ether, address(0));

        vm.prank(address(engine));
        vm.expectRevert("FXPool: insufficient liquidity");
        myrPool.release(MYR_SEED + 1, bob);

        vm.prank(address(engine));
        vm.expectRevert("FXPool: insufficient liquidity");
        myrPool.releasePlatformFee(MYR_SEED + 1);
    }

    function test_FXPool_InitialDepositTooSmallAndZeroRatePaths() public {
        vm.startPrank(owner);
        FXPool freshPool = new FXPool(
            address(myr),
            address(myrOracle),
            "Tiny MYR",
            "twMYR",
            BASE_FEE_RATE,
            UTILIZATION_FACTOR,
            MAX_DYNAMIC_FEE,
            PLATFORM_FEE_BPS,
            treasury,
            owner
        );
        vm.stopPrank();

        assertEq(freshPool.lpToStablecoinRate(), 1e18);
        assertEq(freshPool.getEffectiveFeeRate(1 ether), MAX_DYNAMIC_FEE);

        vm.startPrank(bob);
        myr.approve(address(freshPool), 1000);
        vm.expectRevert("FXPool: initial deposit too small");
        freshPool.deposit(1000);
        vm.stopPrank();
    }

    function test_LPToken_MintRevertFromNonPool() public {
        LPToken wMYR = LPToken(myrPool.lpToken());
        vm.prank(alice);
        vm.expectRevert();
        wMYR.mint(alice, 1 ether);
    }

    function test_RegisterPool_RevertFromNonOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        engine.registerPool(address(myr), address(myrPool));
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function test_Swap_SameToken_Reverts() public {
        vm.startPrank(bob);
        myr.approve(address(engine), 100 ether);
        vm.expectRevert("FXEngine: same token");
        engine.swap(address(myr), address(myr), 100 ether, 0, bob);
        vm.stopPrank();
    }

    function test_Swap_ZeroAmount_Reverts() public {
        vm.startPrank(bob);
        myr.approve(address(engine), 0);
        vm.expectRevert("FXEngine: zero amountIn");
        engine.swap(address(myr), address(sgd), 0, 0, bob);
        vm.stopPrank();
    }

    function test_Swap_InputValidationAndPauseBranches() public {
        vm.expectRevert("FXEngine: zero recipient");
        engine.swap(address(myr), address(sgd), 1 ether, 0, address(0));

        vm.expectRevert("FXEngine: no pool for tokenIn");
        engine.swap(makeAddr("missingIn"), address(sgd), 1 ether, 0, bob);

        vm.expectRevert("FXEngine: no pool for tokenOut");
        engine.swap(address(myr), makeAddr("missingOut"), 1 ether, 0, bob);

        vm.prank(owner);
        engine.pause();

        vm.startPrank(bob);
        myr.approve(address(engine), 1 ether);
        vm.expectRevert();
        engine.swap(address(myr), address(sgd), 1 ether, 0, bob);
        vm.stopPrank();

        vm.prank(owner);
        engine.unpause();
    }

    function test_GetQuote_RevertsOnInvalidPools() public {
        vm.expectRevert("FXEngine: same token");
        engine.getQuote(address(myr), address(myr), 1 ether);

        vm.expectRevert("FXEngine: no pool for tokenIn");
        engine.getQuote(makeAddr("missingIn"), address(sgd), 1 ether);

        vm.expectRevert("FXEngine: no pool for tokenOut");
        engine.getQuote(address(myr), makeAddr("missingOut"), 1 ether);
    }

    function test_GetQuote_NormalizesMismatchedOracleDecimals() public {
        vm.startPrank(owner);
        MYRToken decHighToken = new MYRToken(owner);
        SGDToken decLowToken = new SGDToken(owner);
        MockOraklFeed decHighFeed = new MockOraklFeed(10, 1_000_000_0000);
        MockOraklFeed decLowFeed = new MockOraklFeed(8, 100_000_000);
        OracleAggregator decHighOracle = new OracleAggregator(
            address(decHighFeed), address(pyth), bytes32(uint256(101)), false, DEVIATION_BPS, owner
        );
        OracleAggregator decLowOracle = new OracleAggregator(
            address(decLowFeed), address(pyth), bytes32(uint256(102)), false, DEVIATION_BPS, owner
        );
        decHighOracle.setCrossValidation(false);
        decLowOracle.setCrossValidation(false);

        FXPool decHighPool = new FXPool(
            address(decHighToken),
            address(decHighOracle),
            "Decimal High",
            "dHIGH",
            BASE_FEE_RATE,
            0,
            MAX_DYNAMIC_FEE,
            0,
            treasury,
            owner
        );
        FXPool decLowPool = new FXPool(
            address(decLowToken),
            address(decLowOracle),
            "Decimal Low",
            "dLOW",
            BASE_FEE_RATE,
            0,
            MAX_DYNAMIC_FEE,
            0,
            treasury,
            owner
        );
        engine.registerPool(address(decHighToken), address(decHighPool));
        engine.registerPool(address(decLowToken), address(decLowPool));

        decHighToken.mint(alice, 100_000 ether);
        decLowToken.mint(alice, 100_000 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        decHighToken.approve(address(decHighPool), 100_000 ether);
        decLowToken.approve(address(decLowPool), 100_000 ether);
        decHighPool.deposit(100_000 ether);
        decLowPool.deposit(100_000 ether);
        vm.stopPrank();

        uint256 highToLow = engine.getQuote(address(decHighToken), address(decLowToken), 1_000 ether);
        uint256 lowToHigh = engine.getQuote(address(decLowToken), address(decHighToken), 1_000 ether);

        assertEq(highToLow, 999 ether);
        assertEq(lowToHigh, 999 ether);
    }

    function test_Deposit_ZeroAmount_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert("FXPool: zero amount");
        myrPool.deposit(0);
        vm.stopPrank();
    }

    function test_GetPoolInfo() public view {
        (address pool, address lpToken, uint256 balance, uint256 baseFee, uint256 maxFee, int256 price, uint8 dec)
            = engine.getPoolInfo(address(myr));
        assertEq(pool,    address(myrPool));
        assertEq(lpToken, myrPool.lpToken());
        assertEq(balance, MYR_SEED);
        assertEq(baseFee, BASE_FEE_RATE);
        assertEq(maxFee,  MAX_DYNAMIC_FEE);
        assertApproxEqAbs(uint256(price), uint256(MYR_USD), uint256(MYR_USD) / 33);
        assertEq(dec, 8);
    }

    // =========================================================================
    // Dynamic fee tests
    // =========================================================================

    function test_DynamicFee_SmallTrade_NearBase() public view {
        // 100 MYR → SGD: grossOut ≈ 30.57 SGD, pool has 305_662 SGD → utilization ~0.01%
        uint256 grossOut = (100 ether * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 rate = sgdPool.getEffectiveFeeRate(grossOut);
        // Should be very close to base fee (10 bps)
        assertEq(rate, BASE_FEE_RATE);
    }

    function test_DynamicFee_LargeTrade_HigherFee() public view {
        // Simulate large trade: 100k MYR → SGD, grossOut ≈ 30_567 SGD
        // Pool has 305_662 SGD → utilization ~10%
        uint256 grossOut = (100_000 ether * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 rate = sgdPool.getEffectiveFeeRate(grossOut);
        // Should be significantly above base fee
        assertGt(rate, BASE_FEE_RATE);
        // utilization = 30567 * 10000 / 305662 ≈ 999 bps
        // feeRate = 10 + (999 * 2000 / 10000) = 10 + 199 = 209 bps
        assertGt(rate, 100);
        assertLe(rate, MAX_DYNAMIC_FEE);
    }

    function test_DynamicFee_HugeTrade_Capped() public view {
        // Very large trade that would exceed max fee
        uint256 poolBal = sgdPool.getPoolBalance();
        uint256 grossOut = poolBal / 2; // 50% of pool
        uint256 rate = sgdPool.getEffectiveFeeRate(grossOut);
        // Must be capped at MAX_DYNAMIC_FEE
        assertEq(rate, MAX_DYNAMIC_FEE);
    }

    function test_DynamicFee_SwapIntegratesDynamicFee() public {
        // Verify that actual swap uses dynamic fee
        uint256 amountIn = 10_000 ether;
        vm.prank(owner);
        myr.mint(bob, amountIn);

        uint256 quoteBefore = engine.getQuote(address(myr), address(sgd), amountIn);

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 actualOut = engine.swap(address(myr), address(sgd), amountIn, quoteBefore, bob);
        vm.stopPrank();

        assertEq(actualOut, quoteBefore);

        // The fee should be higher than base fee for this size
        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 effectiveRate = sgdPool.getEffectiveFeeRate(grossOut);
        assertGt(effectiveRate, BASE_FEE_RATE);
        console.log("10k MYR swap - effective fee rate (bps):", effectiveRate);
    }

    // =========================================================================
    // Platform fee distribution tests
    // =========================================================================

    function test_PlatformFee_70_30_Split() public {
        uint256 amountIn = 1_000 ether;
        vm.prank(owner);
        myr.mint(bob, amountIn);

        uint256 treasuryBalBefore = sgd.balanceOf(treasury);
        uint256 poolBalBefore = sgdPool.getPoolBalance();

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 netOut = engine.swap(address(myr), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        // Compute expected fee
        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 effectiveRate = sgdPool.getEffectiveFeeRate(grossOut);
        uint256 totalFee = (grossOut * effectiveRate) / 10_000;
        uint256 expectedPlatformFee = (totalFee * PLATFORM_FEE_BPS) / 10_000;
        uint256 expectedLpFee = totalFee - expectedPlatformFee;

        // Treasury received platform fee
        uint256 treasuryBalAfter = sgd.balanceOf(treasury);
        assertEq(treasuryBalAfter - treasuryBalBefore, expectedPlatformFee);

        // Pool lost: netOut + platformFee (LP fee stays in pool)
        uint256 poolBalAfter = sgdPool.getPoolBalance();
        assertEq(poolBalBefore - poolBalAfter, netOut + expectedPlatformFee);

        // LP fee = totalFee - platformFee stays in pool implicitly
        assertGt(expectedLpFee, 0);
        assertGt(expectedPlatformFee, 0);

        console.log("Total fee:", totalFee);
        console.log("Platform fee (30%):", expectedPlatformFee);
        console.log("LP fee (70%):", expectedLpFee);
    }

    function test_PlatformFee_TreasuryReceivesCorrectToken() public {
        // Swap USDT → MYR: platform fee should be in MYR (output pool token)
        uint256 amountIn = 100 ether;
        vm.prank(owner);
        usdt.mint(bob, amountIn);

        uint256 treasuryMyrBefore = myr.balanceOf(treasury);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        engine.swap(address(usdt), address(myr), amountIn, 0, bob);
        vm.stopPrank();

        // Treasury should have received MYR (not USDT)
        assertGt(myr.balanceOf(treasury), treasuryMyrBefore);
    }

    function test_PlatformFee_SmallTrade_NearZero() public {
        // Very small trade: fee is tiny, platform fee should be minimal
        uint256 amountIn = 1 ether;
        vm.prank(owner);
        myr.mint(bob, amountIn);

        uint256 treasuryBefore = sgd.balanceOf(treasury);

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        engine.swap(address(myr), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        // Platform fee should be very small but > 0
        uint256 treasuryAfter = sgd.balanceOf(treasury);
        assertGt(treasuryAfter, treasuryBefore);
    }

    function test_PlatformFee_Setters() public {
        vm.startPrank(owner);
        sgdPool.setPlatformFeeBps(5000); // 50%
        assertEq(sgdPool.platformFeeBps(), 5000);

        address newTreasury = makeAddr("newTreasury");
        sgdPool.setPlatformTreasury(newTreasury);
        assertEq(sgdPool.platformTreasury(), newTreasury);
        vm.stopPrank();
    }

    function test_PlatformFee_OnlyOwnerCanSet() public {
        vm.prank(alice);
        vm.expectRevert();
        sgdPool.setPlatformFeeBps(1000);

        vm.prank(alice);
        vm.expectRevert();
        sgdPool.setPlatformTreasury(alice);
    }
}
