// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./mocks/MockOraklFeed.sol";

import "../src/tokens/MYRToken.sol";
import "../src/tokens/SGDToken.sol";
import "../src/tokens/IDRXToken.sol";
import "../src/tokens/USDTToken.sol";

import "../src/pools/FXPool.sol";
import "../src/pools/LPToken.sol";
import "../src/FXEngine.sol";

/// @title FXEngineTest
/// @notice Full integration test suite for the FX engine.
///         Uses MockV3Aggregator which implements the same latestRoundData/decimals
///         ABI as Orakl Network's IAggregator.
contract FXEngineTest is Test {
    // ── Price feed constants (8 decimals, USD) ────────────────────────────────
    int256 constant MYR_USD  = 22_680_000;    // $0.2268
    int256 constant SGD_USD  = 74_190_000;    // $0.7419
    int256 constant IDRX_USD =      6_170;    // $0.0000617
    int256 constant USDT_USD = 100_000_000;   // $1.0000

    uint256 constant FEE_RATE = 30; // 0.30 %

    // ── Actors ─────────────────────────────────────────────────────────────────
    address owner = makeAddr("owner");
    address alice = makeAddr("alice"); // LP provider
    address bob   = makeAddr("bob");   // trader

    // ── Tokens ─────────────────────────────────────────────────────────────────
    MYRToken  myr;
    SGDToken  sgd;
    IDRXToken idrx;
    USDTToken usdt;

    // ── Mock feeds (Orakl v0.2 interface) ────────────────────────────────────
    MockOraklFeed myrFeed;
    MockOraklFeed sgdFeed;
    MockOraklFeed idrxFeed;
    MockOraklFeed usdtFeed;

    // ── Pools & engine ─────────────────────────────────────────────────────────
    FXPool   myrPool;
    FXPool   sgdPool;
    FXPool   idrxPool;
    FXPool   usdtPool;
    FXEngine engine;

    // ── Seed amounts ──────────────────────────────────────────────────────────
    uint256 constant MYR_SEED  =     1_000_000 ether;
    uint256 constant SGD_SEED  =       305_662 ether; // ≈ same USD value as 1M MYR
    uint256 constant IDRX_SEED = 3_677_472_000 ether; // ≈ same USD value
    uint256 constant USDT_SEED =       226_800 ether; // ≈ same USD value

    // ─────────────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(owner);

        // Tokens
        myr  = new MYRToken(owner);
        sgd  = new SGDToken(owner);
        idrx = new IDRXToken(owner);
        usdt = new USDTToken(owner);

        // Mock feeds (Orakl v0.2: 3-value latestRoundData)
        myrFeed  = new MockOraklFeed(8, MYR_USD);
        sgdFeed  = new MockOraklFeed(8, SGD_USD);
        idrxFeed = new MockOraklFeed(8, IDRX_USD);
        usdtFeed = new MockOraklFeed(8, USDT_USD);

        // Pools
        myrPool  = new FXPool(address(myr),  address(myrFeed),  "Wrapped MYR",  "wMYR",  FEE_RATE, owner);
        sgdPool  = new FXPool(address(sgd),  address(sgdFeed),  "Wrapped SGD",  "wSGD",  FEE_RATE, owner);
        idrxPool = new FXPool(address(idrx), address(idrxFeed), "Wrapped IDRX", "wIDRX", FEE_RATE, owner);
        usdtPool = new FXPool(address(usdt), address(usdtFeed), "Wrapped USDT", "wUSDT", FEE_RATE, owner);

        // Engine
        engine = new FXEngine(owner);
        engine.registerPool(address(myr),  address(myrPool));
        engine.registerPool(address(sgd),  address(sgdPool));
        engine.registerPool(address(idrx), address(idrxPool));
        engine.registerPool(address(usdt), address(usdtPool));

        // Authorise engine in pools
        myrPool.setFXEngine(address(engine));
        sgdPool.setFXEngine(address(engine));
        idrxPool.setFXEngine(address(engine));
        usdtPool.setFXEngine(address(engine));

        // Mint to alice (LP) and bob (trader)
        myr.mint(alice,  MYR_SEED  + 10_000 ether);
        sgd.mint(alice,  SGD_SEED  + 10_000 ether);
        idrx.mint(alice, IDRX_SEED + 1_000_000_000 ether);
        usdt.mint(alice, USDT_SEED + 10_000 ether);

        myr.mint(bob,  100_000 ether);
        sgd.mint(bob,  100_000 ether);
        usdt.mint(bob,  10_000 ether);

        vm.stopPrank();

        // Alice provides initial liquidity
        vm.startPrank(alice);
        myr.approve(address(myrPool),   MYR_SEED);
        sgd.approve(address(sgdPool),   SGD_SEED);
        idrx.approve(address(idrxPool), IDRX_SEED);
        usdt.approve(address(usdtPool), USDT_SEED);

        myrPool.deposit(MYR_SEED);
        sgdPool.deposit(SGD_SEED);
        idrxPool.deposit(IDRX_SEED);
        usdtPool.deposit(USDT_SEED);
        vm.stopPrank();
    }

    // =========================================================================
    // Deployment sanity
    // =========================================================================

    function test_PoolsSeeded() public view {
        assertEq(myrPool.getPoolBalance(),  MYR_SEED);
        assertEq(sgdPool.getPoolBalance(),  SGD_SEED);
        assertEq(idrxPool.getPoolBalance(), IDRX_SEED);
        assertEq(usdtPool.getPoolBalance(), USDT_SEED);
    }

    function test_LPTokensMinted() public view {
        LPToken wMYR = LPToken(myrPool.lpToken());
        assertEq(wMYR.balanceOf(alice), MYR_SEED);
    }

    function test_EnginePoolsRegistered() public view {
        assertEq(address(engine.pools(address(myr))),  address(myrPool));
        assertEq(address(engine.pools(address(sgd))),  address(sgdPool));
        assertEq(address(engine.pools(address(idrx))), address(idrxPool));
        assertEq(address(engine.pools(address(usdt))), address(usdtPool));
        assertEq(engine.getRegisteredTokens().length, 4);
    }

    // =========================================================================
    // Price feed
    // =========================================================================

    function test_GetPrice_MYR() public view {
        (int256 price, uint8 dec) = myrPool.getPrice();
        assertEq(price, MYR_USD);
        assertEq(dec, 8);
    }

    function test_GetPrice_IDRX() public view {
        (int256 price,) = idrxPool.getPrice();
        assertEq(price, IDRX_USD);
    }

    // =========================================================================
    // Quote calculation
    // =========================================================================

    /// @dev  100 MYR → SGD
    ///       grossOut = 100e18 × 22_680_000 / 74_190_000 ≈ 30.567 SGD
    ///       fee      = 30.567 × 30 / 10_000            ≈  0.092 SGD
    ///       netOut   ≈ 30.475 SGD
    function test_GetQuote_MYRtoSGD() public view {
        uint256 amountIn = 100 ether;
        uint256 quote = engine.getQuote(address(myr), address(sgd), amountIn);

        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 fee      = (grossOut * FEE_RATE) / 10_000;
        uint256 expected = grossOut - fee;

        assertEq(quote, expected);
        // Rough sanity: 100 MYR ≈ 30–31 SGD
        assertGt(quote, 30 ether);
        assertLt(quote, 31 ether);
    }

    /// @dev  100 USDT → IDRX
    ///       100 USD / $0.0000617 per IDRX ≈ 1_620_745 IDRX
    function test_GetQuote_USDTtoIDRX() public view {
        uint256 amountIn = 100 ether;
        uint256 quote = engine.getQuote(address(usdt), address(idrx), amountIn);

        uint256 grossOut = (amountIn * uint256(USDT_USD)) / uint256(IDRX_USD);
        uint256 fee      = (grossOut * FEE_RATE) / 10_000;
        uint256 expected = grossOut - fee;

        assertEq(quote, expected);
        // Sanity: 100 USDT ≈ 1_600_000 – 1_700_000 IDRX
        assertGt(quote, 1_600_000 ether);
        assertLt(quote, 1_700_000 ether);
    }

    function test_GetQuote_IDRXtoUSDT() public view {
        uint256 amountIn = 1_000_000 ether;
        uint256 quote = engine.getQuote(address(idrx), address(usdt), amountIn);

        // 1_000_000 IDR × $0.0000617 ≈ $61.7 USDT
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
        assertEq(sgdPool.getPoolBalance(), SGD_SEED - actualOut);
    }

    function test_Swap_SGDtoMYR() public {
        uint256 amountIn = 305 ether;

        vm.startPrank(bob);
        sgd.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(sgd), address(myr), amountIn, 0, bob);
        vm.stopPrank();

        // Rough sanity: 305 SGD ≈ 1 000 MYR (after fee)
        assertGt(out, 950 ether);
        assertLt(out, 1100 ether);
    }

    function test_Swap_USDTtoIDRX() public {
        uint256 amountIn = 10 ether;

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(idrx), amountIn, 0, bob);
        vm.stopPrank();

        // 10 USDT → ~162_000 IDRX
        assertGt(out, 160_000 ether);
        assertLt(out, 170_000 ether);
    }

    function test_Swap_USDTtoSGD() public {
        uint256 amountIn = 1_000 ether;

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        // 1 000 USD → ~1 348 SGD
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
        assertEq(wMYR.totalSupply(),       1_500_000 ether);

        vm.startPrank(lp2);
        uint256 returned = myrPool.withdraw(lpMinted);
        vm.stopPrank();

        assertEq(returned, 500_000 ether);
        assertEq(myr.balanceOf(lp2), 500_000 ether);
    }

    function test_LP_FeeAccruesToOutPool() public {
        FXPool sgdP = sgdPool;
        LPToken wSGD = LPToken(sgdP.lpToken());

        uint256 supplyBefore  = wSGD.totalSupply();
        uint256 balanceBefore = sgdP.getPoolBalance();

        uint256 amountIn = 1_000 ether;
        vm.prank(owner);
        myr.mint(bob, amountIn);

        vm.startPrank(bob);
        myr.approve(address(engine), amountIn);
        uint256 netOut = engine.swap(address(myr), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        uint256 grossOut = (amountIn * uint256(MYR_USD)) / uint256(SGD_USD);
        uint256 fee      = (grossOut * FEE_RATE) / 10_000;

        uint256 balanceAfter = sgdP.getPoolBalance();
        assertEq(balanceAfter, balanceBefore - netOut);
        assertEq(wSGD.totalSupply(), supplyBefore);

        uint256 rateBefore = (balanceBefore * 1e18) / supplyBefore;
        uint256 rateAfter  = (balanceAfter  * 1e18) / wSGD.totalSupply();

        assertLt(rateAfter, rateBefore);
        assertEq(balanceBefore - balanceAfter, netOut);
        assertEq(grossOut - netOut, fee);
        assertGt(fee, 0);

        console.log("Fee earned by sgdPool LPs:", fee);
        console.log("wSGD rate before (e18):", rateBefore);
        console.log("wSGD rate after  (e18):", rateAfter);
    }

    // =========================================================================
    // Pool admin
    // =========================================================================

    function test_SetFeeRate() public {
        vm.prank(owner);
        myrPool.setFeeRate(50);
        assertEq(myrPool.feeRate(), 50);
    }

    function test_SetFeeRate_RevertOverMax() public {
        vm.prank(owner);
        vm.expectRevert("FXPool: fee too high");
        myrPool.setFeeRate(1_001);
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

    function test_Deposit_ZeroAmount_Reverts() public {
        vm.startPrank(alice);
        vm.expectRevert("FXPool: zero amount");
        myrPool.deposit(0);
        vm.stopPrank();
    }

    function test_GetPoolInfo() public view {
        (address pool, address lpToken, uint256 balance, uint256 fee, int256 price, uint8 dec)
            = engine.getPoolInfo(address(myr));
        assertEq(pool,    address(myrPool));
        assertEq(lpToken, myrPool.lpToken());
        assertEq(balance, MYR_SEED);
        assertEq(fee,     FEE_RATE);
        assertEq(price,   MYR_USD);
        assertEq(dec, 8);
    }
}
