// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./mocks/MockOraklFeed.sol";
import "./mocks/MockPendleSY.sol";
import "./mocks/MockMorphoVault.sol";
import "./mocks/MockStrategy.sol";

import "../src/tokens/USDTToken.sol";
import "../src/tokens/SGDToken.sol";

import "../src/vaults/YieldVault.sol";
import "../src/strategies/PendleStrategy.sol";
import "../src/strategies/MorphoStrategy.sol";
import "../src/FXEngine.sol";

/// @title StrategyAdaptersTest
/// @notice Tests for PendleStrategy, MorphoStrategy, and vault hot-swapping
///         between all three strategy types (Aave mock, Pendle, Morpho).
contract StrategyAdaptersTest is Test {
    // ── Constants ────────────────────────────────────────────────────────────
    int256 constant USDT_USD = 100_000_000;
    int256 constant SGD_USD = 74_190_000;

    uint256 constant FEE_RATE = 30;
    uint256 constant COVERAGE = 2_000; // 20 % liquid

    uint256 constant SEED = 1_000_000 ether;

    // ── Actors ───────────────────────────────────────────────────────────────
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // ── Core contracts ───────────────────────────────────────────────────────
    USDTToken usdt;
    SGDToken sgd;
    MockOraklFeed usdtFeed;
    MockOraklFeed sgdFeed;

    YieldVault usdtVault;
    YieldVault sgdVault;
    FXEngine engine;

    // ── Protocol mocks ───────────────────────────────────────────────────────
    MockPendleSY pendleSY;
    MockMorphoVault morphoMock;

    // ── Strategies ───────────────────────────────────────────────────────────
    PendleStrategy pendleStrat;
    MorphoStrategy morphoStrat;
    MockStrategy simpleStrat; // the Phase-1 mock for baseline comparison

    function setUp() public {
        vm.startPrank(owner);

        // Tokens & feeds
        usdt = new USDTToken(owner);
        sgd = new SGDToken(owner);
        usdtFeed = new MockOraklFeed(8, USDT_USD);
        sgdFeed = new MockOraklFeed(8, SGD_USD);

        // Vaults
        usdtVault = new YieldVault(
            IERC20(address(usdt)), address(usdtFeed), "USDT Yield Vault", "yvUSDT", FEE_RATE, COVERAGE, owner
        );
        sgdVault = new YieldVault(
            IERC20(address(sgd)), address(sgdFeed), "SGD Yield Vault", "yvSGD", FEE_RATE, COVERAGE, owner
        );

        // Protocol mocks
        pendleSY = new MockPendleSY(address(usdt));
        morphoMock = new MockMorphoVault(address(usdt));

        // Strategies (all for USDT vault)
        pendleStrat = new PendleStrategy(address(usdtVault), address(usdt), address(pendleSY));
        morphoStrat = new MorphoStrategy(address(usdtVault), address(usdt), address(morphoMock));
        simpleStrat = new MockStrategy(address(usdtVault), address(usdt));

        // Engine
        engine = new FXEngine(owner, address(0));
        engine.registerPool(address(usdt), address(usdtVault));
        engine.registerPool(address(sgd), address(sgdVault));
        usdtVault.proposeEngine(address(engine));
        usdtVault.acceptEngine();
        sgdVault.proposeEngine(address(engine));
        sgdVault.acceptEngine();

        // Mint & seed
        usdt.mint(alice, SEED + 200_000 ether);
        sgd.mint(alice, SEED + 200_000 ether);
        usdt.mint(bob, 50_000 ether);
        sgd.mint(bob, 50_000 ether);

        vm.stopPrank();

        // Alice seeds both vaults
        vm.startPrank(alice);
        usdt.approve(address(usdtVault), SEED);
        sgd.approve(address(sgdVault), SEED);
        usdtVault.deposit(SEED);
        sgdVault.deposit(SEED);
        vm.stopPrank();
    }

    // =====================================================================
    //  PENDLE STRATEGY
    // =====================================================================

    function test_Pendle_DeployAndRebalance() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        assertEq(usdtVault.liquidReserve(), 200_000 ether);
        assertEq(usdtVault.deployedCapital(), 800_000 ether);
        assertEq(usdtVault.totalAssets(), SEED);
    }

    function test_Pendle_Harvest() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance(); // 800k deployed
        vm.stopPrank();

        uint256 sharesBefore = usdtVault.totalSupply();
        uint256 totalBefore = usdtVault.totalAssets();

        // Simulate 5% yield on Pendle SY
        // 800k deposited → 800k SY at rate 1.0 → rate becomes 1.05
        vm.startPrank(owner);
        uint256 yield_ = 40_000 ether; // 5% of 800k
        usdt.mint(address(pendleSY), yield_);
        pendleSY.setExchangeRate(1.05e18);
        vm.stopPrank();

        // Verify totalValue reflects yield
        assertEq(usdtVault.deployedCapital(), 840_000 ether);

        // Harvest (allow 1 wei rounding from SY share ↔ underlying conversion)
        vm.prank(owner);
        uint256 profit = usdtVault.harvest();
        assertApproxEqAbs(profit, yield_, 1);

        // Share value increased
        assertEq(usdtVault.totalSupply(), sharesBefore);
        assertGt(usdtVault.totalAssets(), totalBefore);

        console.log("Pendle yield harvested:", profit);
        console.log("Share value (e18):", (usdtVault.totalAssets() * 1e18) / sharesBefore);
    }

    function test_Pendle_WithdrawRecalls() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance(); // 200k liquid
        vm.stopPrank();

        // Alice withdraws 500k (exceeds 200k liquid → must recall from Pendle)
        vm.startPrank(alice);
        uint256 returned = usdtVault.withdraw(500_000 ether);
        vm.stopPrank();

        assertEq(returned, 500_000 ether);
        assertEq(usdtVault.totalAssets(), 500_000 ether);
    }

    function test_Pendle_SwapThroughVault() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        uint256 amountIn = 1_000 ether;
        uint256 quote = engine.getQuote(address(usdt), address(sgd), amountIn);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(sgd), amountIn, quote, bob);
        vm.stopPrank();

        assertEq(out, quote);
    }

    // =====================================================================
    //  MORPHO STRATEGY
    // =====================================================================

    function test_Morpho_DeployAndRebalance() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        assertEq(usdtVault.liquidReserve(), 200_000 ether);
        assertEq(usdtVault.deployedCapital(), 800_000 ether);
        assertEq(usdtVault.totalAssets(), SEED);
    }

    function test_Morpho_Harvest() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance(); // 800k deployed
        vm.stopPrank();

        uint256 sharesBefore = usdtVault.totalSupply();
        uint256 totalBefore = usdtVault.totalAssets();

        // Simulate 3% yield on Morpho vault
        // Mint extra USDT to the Morpho mock → share price increases automatically
        vm.prank(owner);
        uint256 yield_ = 24_000 ether; // 3% of 800k
        usdt.mint(address(morphoMock), yield_);

        // Verify totalValue reflects yield
        assertEq(usdtVault.deployedCapital(), 824_000 ether);

        // Harvest
        vm.prank(owner);
        uint256 profit = usdtVault.harvest();
        assertEq(profit, yield_);

        assertEq(usdtVault.totalSupply(), sharesBefore);
        assertGt(usdtVault.totalAssets(), totalBefore);

        console.log("Morpho yield harvested:", profit);
        console.log("Share value (e18):", (usdtVault.totalAssets() * 1e18) / sharesBefore);
    }

    function test_Morpho_WithdrawRecalls() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 returned = usdtVault.withdraw(500_000 ether);
        vm.stopPrank();

        assertEq(returned, 500_000 ether);
        assertEq(usdtVault.totalAssets(), 500_000 ether);
    }

    function test_Morpho_SwapThroughVault() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        uint256 amountIn = 1_000 ether;
        uint256 quote = engine.getQuote(address(usdt), address(sgd), amountIn);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(sgd), amountIn, quote, bob);
        vm.stopPrank();

        assertEq(out, quote);
    }

    // =====================================================================
    //  STRATEGY HOT-SWAP: Pendle → Morpho → Mock
    // =====================================================================

    function test_HotSwap_PendleToMorpho() public {
        // Start with Pendle
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        assertEq(usdtVault.deployedCapital(), 800_000 ether);

        // Simulate some Pendle yield
        vm.startPrank(owner);
        usdt.mint(address(pendleSY), 20_000 ether);
        pendleSY.setExchangeRate(1.025e18);
        vm.stopPrank();

        uint256 totalBefore = usdtVault.totalAssets();
        assertEq(totalBefore, 1_020_000 ether); // 200k liquid + 820k in Pendle

        // Hot-swap to Morpho — all Pendle capital is recalled first
        vm.startPrank(owner);
        MorphoStrategy newMorpho = new MorphoStrategy(address(usdtVault), address(usdt), address(morphoMock));
        usdtVault.setStrategy(address(newMorpho));
        vm.stopPrank();

        // All capital back in vault (liquid)
        assertEq(usdtVault.liquidReserve(), 1_020_000 ether);
        assertEq(usdtVault.deployedCapital(), 0);

        // Rebalance into Morpho
        vm.prank(owner);
        usdtVault.rebalance();

        // 20% of 1.02M = 204k liquid, 816k in Morpho
        assertEq(usdtVault.liquidReserve(), 204_000 ether);
        assertEq(usdtVault.deployedCapital(), 816_000 ether);
        assertEq(usdtVault.totalAssets(), 1_020_000 ether);
    }

    function test_HotSwap_MorphoToMock() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        assertEq(usdtVault.deployedCapital(), 800_000 ether);

        // Swap to simple mock
        vm.startPrank(owner);
        MockStrategy newMock = new MockStrategy(address(usdtVault), address(usdt));
        usdtVault.setStrategy(address(newMock));
        vm.stopPrank();

        assertEq(usdtVault.liquidReserve(), SEED);
        assertEq(usdtVault.deployedCapital(), 0);

        vm.prank(owner);
        usdtVault.rebalance();

        assertEq(usdtVault.deployedCapital(), 800_000 ether);
    }

    // =====================================================================
    //  STRATEGY HOT-SWAP preserves share value
    // =====================================================================

    function test_HotSwap_PreservesShareValue() public {
        // Deploy to Pendle and earn yield
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();

        usdt.mint(address(pendleSY), 50_000 ether);
        pendleSY.setExchangeRate(1.0625e18); // 6.25% yield on 800k
        vm.stopPrank();

        uint256 sharePriceBefore = (usdtVault.totalAssets() * 1e18) / usdtVault.totalSupply();

        // Hot-swap to Morpho
        vm.startPrank(owner);
        MorphoStrategy newMorpho = new MorphoStrategy(address(usdtVault), address(usdt), address(morphoMock));
        usdtVault.setStrategy(address(newMorpho));
        usdtVault.rebalance();
        vm.stopPrank();

        uint256 sharePriceAfter = (usdtVault.totalAssets() * 1e18) / usdtVault.totalSupply();

        // Share price must be preserved through the swap
        assertEq(sharePriceAfter, sharePriceBefore);

        console.log("Share price preserved through hot-swap (e18):", sharePriceAfter);
    }

    // =====================================================================
    //  MULTI-HARVEST across different strategies
    // =====================================================================

    function test_MultiHarvest_PendleThenMorpho() public {
        // Phase A: Pendle earns yield
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();

        usdt.mint(address(pendleSY), 10_000 ether);
        pendleSY.setExchangeRate(1.0125e18);
        vm.stopPrank();

        vm.prank(owner);
        uint256 pendleProfit = usdtVault.harvest();
        console.log("Pendle harvest:", pendleProfit);
        assertApproxEqAbs(pendleProfit, 10_000 ether, 1);

        // Phase B: Swap to Morpho, earn yield there
        vm.startPrank(owner);
        MorphoStrategy newMorpho = new MorphoStrategy(address(usdtVault), address(usdt), address(morphoMock));
        usdtVault.setStrategy(address(newMorpho));
        usdtVault.rebalance();

        uint256 deployedInMorpho = usdtVault.deployedCapital();
        uint256 morphoYield = 8_000 ether;
        usdt.mint(address(morphoMock), morphoYield);
        vm.stopPrank();

        vm.prank(owner);
        uint256 morphoProfit = usdtVault.harvest();
        console.log("Morpho harvest:", morphoProfit);
        assertEq(morphoProfit, morphoYield);

        // Total accrued yield ≈ 10k + 8k = 18k (≤2 wei rounding from Pendle SY conversions)
        assertApproxEqAbs(usdtVault.totalAssets(), SEED + 10_000 ether + morphoProfit, 2);

        uint256 sharePrice = (usdtVault.totalAssets() * 1e18) / usdtVault.totalSupply();
        console.log("Final share price (e18):", sharePrice);
        assertApproxEqAbs(sharePrice, 1.018e18, 2);
    }

    // =====================================================================
    //  ACCESS CONTROL
    // =====================================================================

    function test_Pendle_OnlyVaultCanCallStrategy() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("BaseStrategy: only vault");
        pendleStrat.deposit(1_000 ether);

        vm.prank(alice);
        vm.expectRevert("BaseStrategy: only vault");
        pendleStrat.withdraw(1_000 ether);

        vm.prank(alice);
        vm.expectRevert("BaseStrategy: only vault");
        pendleStrat.harvest();
    }

    function test_Morpho_OnlyVaultCanCallStrategy() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert("BaseStrategy: only vault");
        morphoStrat.deposit(1_000 ether);

        vm.prank(alice);
        vm.expectRevert("BaseStrategy: only vault");
        morphoStrat.withdraw(1_000 ether);

        vm.prank(alice);
        vm.expectRevert("BaseStrategy: only vault");
        morphoStrat.harvest();
    }

    // =====================================================================
    //  EDGE: harvest with zero yield
    // =====================================================================

    function test_Pendle_HarvestZeroYield() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();

        uint256 profit = usdtVault.harvest();
        vm.stopPrank();
        assertEq(profit, 0);
    }

    function test_Morpho_HarvestZeroYield() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance();

        uint256 profit = usdtVault.harvest();
        vm.stopPrank();
        assertEq(profit, 0);
    }

    // =====================================================================
    //  EDGE: full withdrawal drains strategy
    // =====================================================================

    function test_Pendle_FullWithdrawal() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(pendleStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        // Withdraw all of alice's shares (dead shares remain permanently locked)
        uint256 DEAD = 1000;
        vm.startPrank(alice);
        usdtVault.withdraw(usdtVault.balanceOf(alice));
        vm.stopPrank();

        assertApproxEqAbs(usdtVault.totalAssets(), DEAD, 1);
        assertApproxEqAbs(usdtVault.deployedCapital(), DEAD, 1);
        assertEq(usdtVault.totalSupply(), DEAD);
    }

    function test_Morpho_FullWithdrawal() public {
        vm.startPrank(owner);
        usdtVault.setStrategy(address(morphoStrat));
        usdtVault.rebalance();
        vm.stopPrank();

        uint256 DEAD = 1000;
        vm.startPrank(alice);
        usdtVault.withdraw(usdtVault.balanceOf(alice));
        vm.stopPrank();

        assertApproxEqAbs(usdtVault.totalAssets(), DEAD, 1);
        assertApproxEqAbs(usdtVault.deployedCapital(), DEAD, 1);
        assertEq(usdtVault.totalSupply(), DEAD);
    }
}
