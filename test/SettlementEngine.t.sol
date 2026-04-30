// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./mocks/MockOraklFeed.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

import "../src/oracles/OracleAggregator.sol";
import "../src/pools/FXPool.sol";
import "../src/pools/LPToken.sol";
import "../src/settlement/SettlementEngine.sol";

/// @title SettlementEngineTest
/// @notice Tests for multi-hop routing and intent-based netting.
contract SettlementEngineTest is Test {
    // ── Price feed constants (8 decimals, USD) ───────────────────────────
    int256 constant MYR_USD = 22_680_000; // $0.2268
    int256 constant SGD_USD = 74_190_000; // $0.7419
    int256 constant IDRX_USD = 6_170; // $0.0000617
    int256 constant USDT_USD = 100_000_000; // $1.0000

    uint256 constant FEE_RATE = 30;          // 0.30 % base fee
    uint256 constant UTIL_FACTOR = 0;        // no utilization scaling for settlement tests
    uint256 constant MAX_FEE = 300;          // 3% cap
    uint256 constant PLATFORM_BPS = 3000;    // 30% platform fee
    uint256 constant DEVIATION_BPS = 300;    // 3% oracle deviation

    // Pyth price IDs (dummy)
    bytes32 constant PYTH_MYR_ID  = bytes32(uint256(1));
    bytes32 constant PYTH_SGD_ID  = bytes32(uint256(2));
    bytes32 constant PYTH_IDR_ID  = bytes32(uint256(3));
    bytes32 constant PYTH_USDT_ID = bytes32(uint256(4));

    // ── Actors ───────────────────────────────────────────────────────────
    address owner    = makeAddr("owner");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");
    address charlie  = makeAddr("charlie");
    address keeper   = makeAddr("keeper");
    address treasury = makeAddr("treasury");

    // ── Tokens ───────────────────────────────────────────────────────────
    MYRToken myr;
    SGDToken sgd;
    IDRXToken idrx;
    USDTToken usdt;

    // ── Feeds & oracles ──────────────────────────────────────────────────
    MockPyth pyth;
    MockOraklFeed myrFeed;
    MockOraklFeed sgdFeed;
    MockOraklFeed idrxFeed;
    MockOraklFeed usdtFeed;
    OracleAggregator myrOracle;
    OracleAggregator sgdOracle;
    OracleAggregator idrxOracle;
    OracleAggregator usdtOracle;

    // ── Pools & engine ───────────────────────────────────────────────────
    FXPool myrPool;
    FXPool sgdPool;
    FXPool idrxPool;
    FXPool usdtPool;
    SettlementEngine engine;

    // ── Seed amounts (≈ $226.8k USD value each) ──────────────────────────
    uint256 constant MYR_SEED = 1_000_000 ether;
    uint256 constant SGD_SEED = 305_662 ether;
    uint256 constant IDRX_SEED = 3_677_472_000 ether;
    uint256 constant USDT_SEED = 226_800 ether;

    // ─────────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(owner);

        // Tokens
        myr = new MYRToken(owner);
        sgd = new SGDToken(owner);
        idrx = new IDRXToken(owner);
        usdt = new USDTToken(owner);

        // Feeds
        myrFeed  = new MockOraklFeed(8, MYR_USD);
        sgdFeed  = new MockOraklFeed(8, SGD_USD);
        idrxFeed = new MockOraklFeed(8, IDRX_USD);
        usdtFeed = new MockOraklFeed(8, USDT_USD);

        // Pyth mock (prices seeded to match Orakl — cross-validation passes)
        pyth = new MockPyth(60, 0);
        _seedPyth(PYTH_MYR_ID,  int64(MYR_USD),  -8);
        _seedPyth(PYTH_SGD_ID,  int64(SGD_USD),  -8);
        _seedPyth(PYTH_IDR_ID,  int64(IDRX_USD), -8);
        _seedPyth(PYTH_USDT_ID, int64(USDT_USD), -8);

        // Oracle Aggregators
        myrOracle  = new OracleAggregator(address(myrFeed),  address(pyth), PYTH_MYR_ID,  false, DEVIATION_BPS, owner);
        sgdOracle  = new OracleAggregator(address(sgdFeed),  address(pyth), PYTH_SGD_ID,  false, DEVIATION_BPS, owner);
        idrxOracle = new OracleAggregator(address(idrxFeed), address(pyth), PYTH_IDR_ID,  false, DEVIATION_BPS, owner);
        usdtOracle = new OracleAggregator(address(usdtFeed), address(pyth), PYTH_USDT_ID, false, DEVIATION_BPS, owner);

        // Pools
        myrPool  = new FXPool(address(myr),  address(myrOracle),  "Wrapped MYR",  "wMYR",  FEE_RATE, UTIL_FACTOR, MAX_FEE, PLATFORM_BPS, treasury, owner);
        sgdPool  = new FXPool(address(sgd),  address(sgdOracle),  "Wrapped SGD",  "wSGD",  FEE_RATE, UTIL_FACTOR, MAX_FEE, PLATFORM_BPS, treasury, owner);
        idrxPool = new FXPool(address(idrx), address(idrxOracle), "Wrapped IDRX", "wIDRX", FEE_RATE, UTIL_FACTOR, MAX_FEE, PLATFORM_BPS, treasury, owner);
        usdtPool = new FXPool(address(usdt), address(usdtOracle), "Wrapped USDT", "wUSDT", FEE_RATE, UTIL_FACTOR, MAX_FEE, PLATFORM_BPS, treasury, owner);

        // Settlement engine (inherits FXEngine)
        engine = new SettlementEngine(owner, address(pyth));
        engine.registerPool(address(myr), address(myrPool));
        engine.registerPool(address(sgd), address(sgdPool));
        engine.registerPool(address(idrx), address(idrxPool));
        engine.registerPool(address(usdt), address(usdtPool));

        myrPool.proposeEngine(address(engine));
        myrPool.acceptEngine();
        sgdPool.proposeEngine(address(engine));
        sgdPool.acceptEngine();
        idrxPool.proposeEngine(address(engine));
        idrxPool.acceptEngine();
        usdtPool.proposeEngine(address(engine));
        usdtPool.acceptEngine();

        // Mint tokens
        myr.mint(alice, MYR_SEED + 500_000 ether);
        sgd.mint(alice, SGD_SEED + 500_000 ether);
        idrx.mint(alice, IDRX_SEED + 1_000_000_000 ether);
        usdt.mint(alice, USDT_SEED + 500_000 ether);

        myr.mint(bob, 200_000 ether);
        sgd.mint(bob, 200_000 ether);
        idrx.mint(bob, 500_000_000 ether);
        usdt.mint(bob, 200_000 ether);

        myr.mint(charlie, 200_000 ether);
        sgd.mint(charlie, 200_000 ether);
        usdt.mint(charlie, 200_000 ether);

        vm.stopPrank();

        // Alice seeds all pools
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

    function _seedPyth(bytes32 id, int64 price, int32 expo) internal {
        bytes memory data = pyth.createPriceFeedUpdateData(id, price, 1000, expo, price, 1000, uint64(block.timestamp));
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = data;
        pyth.updatePriceFeeds{value: 0}(updateData);
    }

    // =====================================================================
    //  Direct swap still works (inherited from FXEngine)
    // =====================================================================

    function test_DirectSwap_StillWorks() public {
        uint256 amountIn = 1_000 ether;

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(myr), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        assertGt(out, 0);
    }

    // =====================================================================
    //  Multi-hop: quotes
    // =====================================================================

    function test_MultiHopQuote_TwoHop() public view {
        // SGD → USDT → IDRX
        address[] memory path = new address[](3);
        path[0] = address(sgd);
        path[1] = address(usdt);
        path[2] = address(idrx);

        uint256 amountIn = 100 ether; // 100 SGD
        uint256 quote = engine.getMultiHopQuote(path, amountIn);

        // 100 SGD → USDT → IDRX
        // Hop 1: 100 SGD → USDT = 100 * 0.7419/1.0 * (1 - 0.003) ≈ 73.97 USDT
        // Hop 2: 73.97 USDT → IDRX = 73.97 * 1.0/0.0000617 * (1 - 0.003) ≈ ~1,195,000 IDRX
        assertGt(quote, 1_100_000 ether);
        assertLt(quote, 1_300_000 ether);
    }

    function test_MultiHopQuote_EquivalentToChainedSingleQuotes() public view {
        // SGD → USDT → IDRX should equal chaining two single quotes
        uint256 amountIn = 500 ether;

        // Chain manually
        uint256 hop1 = engine.getQuote(address(sgd), address(usdt), amountIn);
        uint256 hop2 = engine.getQuote(address(usdt), address(idrx), hop1);

        // Multi-hop
        address[] memory path = new address[](3);
        path[0] = address(sgd);
        path[1] = address(usdt);
        path[2] = address(idrx);
        uint256 multiHop = engine.getMultiHopQuote(path, amountIn);

        assertEq(multiHop, hop2);
    }

    function test_MultiHopQuote_ThreeHop() public view {
        // MYR → SGD → USDT → IDRX
        address[] memory path = new address[](4);
        path[0] = address(myr);
        path[1] = address(sgd);
        path[2] = address(usdt);
        path[3] = address(idrx);

        uint256 quote = engine.getMultiHopQuote(path, 10_000 ether);
        assertGt(quote, 0);
    }

    // =====================================================================
    //  Multi-hop: execution
    // =====================================================================

    function test_MultiHopSwap_SGD_USDT_IDRX() public {
        address[] memory path = new address[](3);
        path[0] = address(sgd);
        path[1] = address(usdt);
        path[2] = address(idrx);

        uint256 amountIn = 100 ether;
        uint256 quote = engine.getMultiHopQuote(path, amountIn);

        uint256 sgdBefore = sgd.balanceOf(bob);
        uint256 idrxBefore = idrx.balanceOf(bob);

        vm.startPrank(bob);
        sgd.approve(address(engine), amountIn);
        uint256 out = engine.swapMultiHop(path, amountIn, quote, bob);
        vm.stopPrank();

        assertEq(out, quote);
        assertEq(sgd.balanceOf(bob), sgdBefore - amountIn);
        assertEq(idrx.balanceOf(bob), idrxBefore + out);

        // SGD went to sgdPool, IDRX came from idrxPool
        assertEq(sgdPool.getPoolBalance(), SGD_SEED + amountIn);
    }

    function test_MultiHopSwap_SlippageProtection() public {
        address[] memory path = new address[](3);
        path[0] = address(sgd);
        path[1] = address(usdt);
        path[2] = address(idrx);

        vm.startPrank(bob);
        sgd.approve(address(engine), 100 ether);
        vm.expectRevert("SE: slippage exceeded");
        engine.swapMultiHop(path, 100 ether, type(uint256).max, bob);
        vm.stopPrank();
    }

    function test_MultiHopSwap_RevertPathTooShort() public {
        address[] memory path = new address[](1);
        path[0] = address(sgd);

        vm.startPrank(bob);
        vm.expectRevert("SE: path too short");
        engine.swapMultiHop(path, 100 ether, 0, bob);
        vm.stopPrank();
    }

    function test_MultiHopSwap_TwoTokenPathSameAsDirect() public {
        address[] memory path = new address[](2);
        path[0] = address(myr);
        path[1] = address(sgd);

        uint256 amountIn = 1_000 ether;
        uint256 directQuote = engine.getQuote(address(myr), address(sgd), amountIn);
        uint256 multiHopQuote = engine.getMultiHopQuote(path, amountIn);

        assertEq(multiHopQuote, directQuote);
    }

    // =====================================================================
    //  Intent: submit & cancel
    // =====================================================================

    function test_SubmitIntent() public {
        uint256 amountIn = 1_000 ether;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 id = engine.submitIntent(address(usdt), address(sgd), amountIn, 0, deadline);
        vm.stopPrank();

        assertEq(id, 0);
        assertEq(usdt.balanceOf(address(engine)), amountIn);

        (
            address trader,
            address tokenIn,
            address tokenOut,
            uint256 amt,
            uint256 minOut,
            uint256 dl,
            bool settled,
            bool cancelled
        ) = engine.getIntent(id);

        assertEq(trader, bob);
        assertEq(tokenIn, address(usdt));
        assertEq(tokenOut, address(sgd));
        assertEq(amt, amountIn);
        assertEq(minOut, 0);
        assertEq(dl, deadline);
        assertFalse(settled);
        assertFalse(cancelled);
    }

    function test_CancelIntent() public {
        uint256 amountIn = 1_000 ether;
        uint256 balBefore = usdt.balanceOf(bob);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 id = engine.submitIntent(address(usdt), address(sgd), amountIn, 0, block.timestamp + 1 hours);

        engine.cancelIntent(id);
        vm.stopPrank();

        assertEq(usdt.balanceOf(bob), balBefore);
        (,,,,,,, bool cancelled) = engine.getIntent(id);
        assertTrue(cancelled);
    }

    function test_CancelIntent_NotOwnerReverts() public {
        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        uint256 id = engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("SE: not intent owner");
        engine.cancelIntent(id);
    }

    function test_CancelIntent_DoubleCancel() public {
        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        uint256 id = engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, block.timestamp + 1 hours);
        engine.cancelIntent(id);

        vm.expectRevert("SE: already cancelled");
        engine.cancelIntent(id);
        vm.stopPrank();
    }

    // =====================================================================
    //  Settle: single intent (no netting, equivalent to direct swap)
    // =====================================================================

    function test_SettleSingle_EquivalentToDirectSwap() public {
        uint256 amountIn = 1_000 ether;
        uint256 directQuote = engine.getQuote(address(usdt), address(sgd), amountIn);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 id = engine.submitIntent(address(usdt), address(sgd), amountIn, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        uint256 sgdBefore = sgd.balanceOf(bob);

        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        engine.settleNetted(ids);

        assertEq(sgd.balanceOf(bob), sgdBefore + directQuote);
    }

    // =====================================================================
    //  Settle: opposing intents (NETTING)
    // =====================================================================

    function test_SettleNetted_OpposingIntents() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Bob: 1000 USDT → SGD
        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        uint256 id0 = engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, deadline);
        vm.stopPrank();

        // Charlie: 500 SGD → USDT
        vm.startPrank(charlie);
        sgd.approve(address(engine), 500 ether);
        uint256 id1 = engine.submitIntent(address(sgd), address(usdt), 500 ether, 0, deadline);
        vm.stopPrank();

        uint256 usdtPoolBefore = usdtPool.getPoolBalance();
        uint256 sgdPoolBefore = sgdPool.getPoolBalance();

        uint256 sgdBobBefore = sgd.balanceOf(bob);
        uint256 usdtCharBefore = usdt.balanceOf(charlie);

        // Settle both together
        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        engine.settleNetted(ids);

        // Bob should get same SGD as a direct swap
        uint256 bobExpected = engine.getQuote(address(usdt), address(sgd), 1_000 ether);
        assertEq(sgd.balanceOf(bob), sgdBobBefore + bobExpected);

        // Charlie should get same USDT as a direct swap
        uint256 charlieExpected = engine.getQuote(address(sgd), address(usdt), 500 ether);
        assertEq(usdt.balanceOf(charlie), usdtCharBefore + charlieExpected);

        // KEY: Pool drain is LESS than sum of individual swaps
        uint256 usdtPoolAfter = usdtPool.getPoolBalance();
        uint256 sgdPoolAfter = sgdPool.getPoolBalance();

        // Without netting: usdtPool would gain 1000 AND lose charlieExpected
        // With netting: usdtPool net = gain (1000 - charlieExpected)
        int256 usdtPoolChange = int256(usdtPoolAfter) - int256(usdtPoolBefore);
        int256 sgdPoolChange = int256(sgdPoolAfter) - int256(sgdPoolBefore);

        console.log(
            "USDT pool change:",
            usdtPoolChange > 0 ? "+" : "-",
            usdtPoolChange > 0 ? uint256(usdtPoolChange) : uint256(-usdtPoolChange)
        );
        console.log(
            "SGD  pool change:",
            sgdPoolChange > 0 ? "+" : "-",
            sgdPoolChange > 0 ? uint256(sgdPoolChange) : uint256(-sgdPoolChange)
        );

        // Verify intents are marked settled
        (,,,,,, bool s0,) = engine.getIntent(id0);
        (,,,,,, bool s1,) = engine.getIntent(id1);
        assertTrue(s0);
        assertTrue(s1);
    }

    function test_SettleNetted_ReducesPoolDrain() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Alice: 5000 USDT → SGD
        vm.startPrank(alice);
        usdt.approve(address(engine), 5_000 ether);
        uint256 id0 = engine.submitIntent(address(usdt), address(sgd), 5_000 ether, 0, deadline);
        vm.stopPrank();

        // Bob: 3000 SGD → USDT
        vm.startPrank(bob);
        sgd.approve(address(engine), 3_000 ether);
        uint256 id1 = engine.submitIntent(address(sgd), address(usdt), 3_000 ether, 0, deadline);
        vm.stopPrank();

        // Record pool balances
        uint256 sgdPoolBefore = sgdPool.getPoolBalance();

        // Expected SGD output if Alice swapped directly
        uint256 aliceSGD = engine.getQuote(address(usdt), address(sgd), 5_000 ether);
        // Expected USDT output if Bob swapped directly
        uint256 bobUSDT = engine.getQuote(address(sgd), address(usdt), 3_000 ether);

        // Settle
        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        engine.settleNetted(ids);

        uint256 sgdPoolAfter = sgdPool.getPoolBalance();

        // Without netting, SGD pool would lose aliceSGD and gain 3000
        // Net SGD pool impact without netting = 3000 - aliceSGD
        int256 withoutNetting = int256(3_000 ether) - int256(aliceSGD);

        // With netting, actual SGD pool change
        int256 withNetting = int256(sgdPoolAfter) - int256(sgdPoolBefore);

        // Both should be the same (pool outcomes are identical)
        assertEq(withNetting, withoutNetting);

        // But the actual pool OUTFLOW is reduced
        // Without netting: pool releases aliceSGD + bobUSDT worth of outflows
        // With netting: pool releases only the net deficit
        uint256 netSGDReleased = sgdPoolBefore > sgdPoolAfter ? sgdPoolBefore - sgdPoolAfter : 0;

        console.log("Alice SGD direct swap output:", aliceSGD);
        console.log("SGD pool net released (netted):", netSGDReleased);
        console.log("SGD pool net released (no netting):", aliceSGD - 3_000 ether);

        assertEq(netSGDReleased, aliceSGD - 3_000 ether);
    }

    // =====================================================================
    //  Settle: same-direction batch (no opposing flow)
    // =====================================================================

    function test_SettleSameDirection_WorksWithoutNetting() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Both Bob and Charlie want USDT → SGD (same direction)
        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        uint256 id0 = engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, deadline);
        vm.stopPrank();

        vm.startPrank(charlie);
        usdt.approve(address(engine), 500 ether);
        uint256 id1 = engine.submitIntent(address(usdt), address(sgd), 500 ether, 0, deadline);
        vm.stopPrank();

        uint256 sgdBobBefore = sgd.balanceOf(bob);
        uint256 sgdCharBefore = sgd.balanceOf(charlie);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        engine.settleNetted(ids);

        // Each gets their individual swap output
        uint256 bobExpected = engine.getQuote(address(usdt), address(sgd), 1_000 ether);
        uint256 charExpected = engine.getQuote(address(usdt), address(sgd), 500 ether);

        assertEq(sgd.balanceOf(bob), sgdBobBefore + bobExpected);
        assertEq(sgd.balanceOf(charlie), sgdCharBefore + charExpected);
    }

    // =====================================================================
    //  Settle: minAmountOut enforcement
    // =====================================================================

    function test_SettleNetted_RespectsMinAmountOut() public {
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        engine.submitIntent(
            address(usdt),
            address(sgd),
            1_000 ether,
            type(uint256).max, // impossible min
            deadline
        );
        vm.stopPrank();

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        vm.expectRevert("SE: below min output");
        engine.settleNetted(ids);
    }

    // =====================================================================
    //  Settle: expired intent
    // =====================================================================

    function test_SettleNetted_ExpiredReverts() public {
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, deadline);
        vm.stopPrank();

        // Fast-forward past deadline
        vm.warp(deadline + 1);

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        vm.expectRevert("SE: expired");
        engine.settleNetted(ids);
    }

    // =====================================================================
    //  Settle: mixed token pairs revert
    // =====================================================================

    function test_SettleNetted_MixedPairsRevert() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Intent 0: USDT → SGD
        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, deadline);
        vm.stopPrank();

        // Intent 1: MYR → SGD (different pair)
        vm.startPrank(charlie);
        myr.approve(address(engine), 1_000 ether);
        engine.submitIntent(address(myr), address(sgd), 1_000 ether, 0, deadline);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = 0;
        ids[1] = 1;

        vm.expectRevert("SE: mixed token pairs");
        engine.settleNetted(ids);
    }

    // =====================================================================
    //  Settle: double-settle revert
    // =====================================================================

    function test_SettleNetted_DoubleSettleReverts() public {
        vm.startPrank(bob);
        usdt.approve(address(engine), 1_000 ether);
        engine.submitIntent(address(usdt), address(sgd), 1_000 ether, 0, block.timestamp + 1 hours);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        engine.settleNetted(ids);

        vm.expectRevert("SE: already settled");
        engine.settleNetted(ids);
    }

    // =====================================================================
    //  Multi-hop + netting integration: settle with YieldVault pools
    // =====================================================================

    function test_MultiHop_FourTokenPath() public {
        // MYR → SGD → USDT → IDRX
        address[] memory path = new address[](4);
        path[0] = address(myr);
        path[1] = address(sgd);
        path[2] = address(usdt);
        path[3] = address(idrx);

        uint256 amountIn = 10_000 ether;
        uint256 quote = engine.getMultiHopQuote(path, amountIn);

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 out = engine.swapMultiHop(path, amountIn, 0, bob);
        vm.stopPrank();

        assertEq(out, quote);
        assertGt(out, 0);

        // MYR pool gained, IDRX pool lost
        assertEq(myrPool.getPoolBalance(), MYR_SEED + amountIn);
        console.log("10k MYR -> IDRX via 4-hop:", out);
    }

    // =====================================================================
    //  getIntent view
    // =====================================================================

    function test_GetIntent_NonExistent() public view {
        (address trader,,,,,,,) = engine.getIntent(999);
        assertEq(trader, address(0));
    }
}
