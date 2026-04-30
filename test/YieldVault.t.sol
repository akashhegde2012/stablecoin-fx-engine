// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./mocks/MockOraklFeed.sol";
import "./mocks/MockStrategy.sol";

import "../src/tokens/USDTToken.sol";
import "../src/tokens/SGDToken.sol";

import "../src/vaults/YieldVault.sol";
import "../src/FXEngine.sol";

/// @title YieldVaultTest
/// @notice Integration tests for the ERC-4626 YieldVault and strategy layer.
contract YieldVaultTest is Test {
    // ── Constants ────────────────────────────────────────────────────────────
    int256 constant USDT_USD = 100_000_000; // $1.00
    int256 constant SGD_USD = 74_190_000; // $0.7419

    uint256 constant FEE_RATE = 30; // 0.30 %
    uint256 constant COVERAGE_RATIO = 2_000; // 20 % liquid

    uint256 constant SEED = 1_000_000 ether;

    // ── Actors ───────────────────────────────────────────────────────────────
    address owner = makeAddr("owner");
    address alice = makeAddr("alice"); // LP
    address bob = makeAddr("bob"); // trader

    // ── Contracts ────────────────────────────────────────────────────────────
    USDTToken usdt;
    SGDToken sgd;

    MockOraklFeed usdtFeed;
    MockOraklFeed sgdFeed;

    YieldVault usdtVault;
    YieldVault sgdVault;
    MockStrategy usdtStrategy;

    FXEngine engine;

    // =====================================================================
    //  Setup
    // =====================================================================

    function setUp() public {
        vm.startPrank(owner);

        // ── Tokens & feeds ──────────────────────────────────────────────
        usdt = new USDTToken(owner);
        sgd = new SGDToken(owner);
        usdtFeed = new MockOraklFeed(8, USDT_USD);
        sgdFeed = new MockOraklFeed(8, SGD_USD);

        // ── Vaults (ERC-4626 pools) ─────────────────────────────────────
        usdtVault = new YieldVault(
            IERC20(address(usdt)), address(usdtFeed), "USDT Yield Vault", "yvUSDT", FEE_RATE, COVERAGE_RATIO, owner
        );

        sgdVault = new YieldVault(
            IERC20(address(sgd)), address(sgdFeed), "SGD Yield Vault", "yvSGD", FEE_RATE, COVERAGE_RATIO, owner
        );

        // ── Strategy (USDT vault only for now) ─────────────────────────
        usdtStrategy = new MockStrategy(address(usdtVault), address(usdt));
        usdtVault.setStrategy(address(usdtStrategy));

        // ── FXEngine ────────────────────────────────────────────────────
        engine = new FXEngine(owner, address(0));
        engine.registerPool(address(usdt), address(usdtVault));
        engine.registerPool(address(sgd), address(sgdVault));

        usdtVault.proposeEngine(address(engine));
        usdtVault.acceptEngine();
        sgdVault.proposeEngine(address(engine));
        sgdVault.acceptEngine();

        // ── Mint & seed liquidity ───────────────────────────────────────
        usdt.mint(alice, SEED + 100_000 ether);
        sgd.mint(alice, SEED + 100_000 ether);
        usdt.mint(bob, 50_000 ether);
        sgd.mint(bob, 50_000 ether);

        vm.stopPrank();

        vm.startPrank(alice);
        usdt.approve(address(usdtVault), SEED);
        sgd.approve(address(sgdVault), SEED);

        // Deposit via IFXPool interface
        usdtVault.deposit(SEED);
        sgdVault.deposit(SEED);
        vm.stopPrank();
    }

    // =====================================================================
    //  Deployment sanity
    // =====================================================================

    function test_VaultSeeded() public view {
        assertEq(usdtVault.totalAssets(), SEED);
        assertEq(sgdVault.totalAssets(), SEED);
    }

    function test_SharesMinted() public view {
        uint256 DEAD = 1000;
        assertEq(usdtVault.balanceOf(alice), SEED - DEAD);
        assertEq(sgdVault.balanceOf(alice), SEED - DEAD);
    }

    function test_VaultIsLPToken() public view {
        assertEq(usdtVault.lpToken(), address(usdtVault));
    }

    function test_StablecoinMatchesAsset() public view {
        assertEq(usdtVault.stablecoin(), address(usdt));
    }

    function test_GetPrice() public view {
        (int256 price, uint8 dec) = usdtVault.getPrice();
        assertEq(price, USDT_USD);
        assertEq(dec, 8);
    }

    // =====================================================================
    //  ERC-4626 deposit / withdraw
    // =====================================================================

    function test_ERC4626_DepositAndRedeem() public {
        uint256 amount = 10_000 ether;
        uint256 DEAD = 1000;

        vm.startPrank(alice);
        usdt.approve(address(usdtVault), amount);
        uint256 shares = usdtVault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(shares, amount);
        assertEq(usdtVault.balanceOf(alice), SEED - DEAD + amount);

        vm.startPrank(alice);
        uint256 returned = usdtVault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(returned, amount);
    }

    // =====================================================================
    //  IFXPool withdraw
    // =====================================================================

    function test_IFXPool_Withdraw() public {
        uint256 lpAmount = 50_000 ether;

        vm.startPrank(alice);
        uint256 returned = usdtVault.withdraw(lpAmount);
        vm.stopPrank();

        assertEq(returned, lpAmount);
        assertEq(usdt.balanceOf(alice), 100_000 ether + returned);
    }

    // =====================================================================
    //  Strategy: rebalance & coverage ratio
    // =====================================================================

    function test_Rebalance_DeploysExcess() public {
        vm.prank(owner);
        usdtVault.rebalance();

        // 20 % of 1M = 200k liquid, 800k deployed
        uint256 liquid = usdtVault.liquidReserve();
        uint256 deployed = usdtVault.deployedCapital();

        assertEq(liquid, 200_000 ether);
        assertEq(deployed, 800_000 ether);
        assertEq(usdtVault.totalAssets(), SEED);

        uint256 ratio = usdtVault.currentCoverageRatio();
        assertEq(ratio, COVERAGE_RATIO);
    }

    function test_Rebalance_RecallsIfUnder() public {
        // First deploy
        vm.prank(owner);
        usdtVault.rebalance();
        assertEq(usdtVault.liquidReserve(), 200_000 ether);

        // Increase target to 50 % → need to recall
        vm.prank(owner);
        usdtVault.setTargetCoverageRatio(5_000);

        vm.prank(owner);
        usdtVault.rebalance();

        assertEq(usdtVault.liquidReserve(), 500_000 ether);
        assertEq(usdtVault.deployedCapital(), 500_000 ether);
    }

    // =====================================================================
    //  Strategy: harvest
    // =====================================================================

    function test_Harvest_IncreasesShareValue() public {
        vm.prank(owner);
        usdtVault.rebalance(); // 800k deployed

        uint256 sharesBefore = usdtVault.totalSupply();
        uint256 totalBefore = usdtVault.totalAssets();

        // Simulate yield: mint 10k USDT to the strategy (interest earned)
        vm.prank(owner);
        usdt.mint(address(usdtStrategy), 10_000 ether);

        // Harvest
        vm.prank(address(0xdead));
        vm.expectRevert(); // only vault can call strategy.harvest
        usdtStrategy.harvest();

        vm.prank(owner);
        uint256 profit = usdtVault.harvest();
        assertEq(profit, 10_000 ether);

        // Total assets increased, share supply unchanged → share value up
        assertEq(usdtVault.totalAssets(), totalBefore + profit);
        assertEq(usdtVault.totalSupply(), sharesBefore);

        console.log("Share value before (e18):", (totalBefore * 1e18) / sharesBefore);
        console.log("Share value after  (e18):", (usdtVault.totalAssets() * 1e18) / sharesBefore);
    }

    // =====================================================================
    //  Withdraw recalls from strategy when liquid is short
    // =====================================================================

    function test_Withdraw_RecallsFromStrategy() public {
        vm.prank(owner);
        usdtVault.rebalance(); // 200k liquid, 800k deployed

        // Alice withdraws 500k (> 200k liquid) → must recall from strategy
        vm.startPrank(alice);
        uint256 returned = usdtVault.withdraw(500_000 ether);
        vm.stopPrank();

        assertEq(returned, 500_000 ether);
        assertEq(usdtVault.totalAssets(), 500_000 ether);
    }

    // =====================================================================
    //  FXEngine swap through YieldVaults
    // =====================================================================

    function test_Swap_ThroughYieldVaults() public {
        uint256 amountIn = 1_000 ether;

        uint256 expectedOut = engine.getQuote(address(usdt), address(sgd), amountIn);

        uint256 sgdBefore = sgd.balanceOf(bob);
        uint256 usdtBefore = usdt.balanceOf(bob);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 actualOut = engine.swap(address(usdt), address(sgd), amountIn, expectedOut, bob);
        vm.stopPrank();

        assertEq(actualOut, expectedOut);
        assertEq(usdt.balanceOf(bob), usdtBefore - amountIn);
        assertEq(sgd.balanceOf(bob), sgdBefore + actualOut);

        // 1000 USD / 0.7419 ≈ 1348 SGD, minus 0.3 % fee
        assertGt(actualOut, 1_340 ether);
        assertLt(actualOut, 1_360 ether);
    }

    function test_Swap_WithStrategyDeployed() public {
        // Rebalance both vaults
        vm.startPrank(owner);
        MockStrategy sgdStrategy = new MockStrategy(address(sgdVault), address(sgd));
        sgdVault.setStrategy(address(sgdStrategy));
        usdtVault.rebalance();
        sgdVault.rebalance();
        vm.stopPrank();

        // 200k liquid in each vault
        assertEq(usdtVault.liquidReserve(), 200_000 ether);
        assertEq(sgdVault.liquidReserve(), 200_000 ether);

        // Swap 1k USDT → SGD (small, within liquid reserve)
        uint256 amountIn = 1_000 ether;
        uint256 expectedOut = engine.getQuote(address(usdt), address(sgd), amountIn);

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 actualOut = engine.swap(address(usdt), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        assertEq(actualOut, expectedOut);
    }

    function test_Release_RecallsFromStrategy() public {
        vm.startPrank(owner);
        MockStrategy sgdStrategy = new MockStrategy(address(sgdVault), address(sgd));
        sgdVault.setStrategy(address(sgdStrategy));
        sgdVault.rebalance(); // 200k liquid SGD
        vm.stopPrank();

        // Large swap: 100k USDT → SGD (needs ~134k SGD, within 200k liquid)
        // But let's try an even larger one that exceeds liquid
        // 200k USDT → SGD ≈ 269k SGD (exceeds 200k liquid)
        vm.prank(owner);
        usdt.mint(bob, 200_000 ether);

        uint256 amountIn = 200_000 ether;

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        // Should succeed — vault recalls from strategy automatically
        assertGt(out, 260_000 ether);
    }

    // =====================================================================
    //  Strategy swap (setStrategy)
    // =====================================================================

    function test_SetStrategy_RecallsOldCapital() public {
        vm.prank(owner);
        usdtVault.rebalance(); // 800k deployed to usdtStrategy

        uint256 deployedBefore = usdtVault.deployedCapital();
        assertEq(deployedBefore, 800_000 ether);

        // Replace with a new strategy
        vm.startPrank(owner);
        MockStrategy newStrategy = new MockStrategy(address(usdtVault), address(usdt));
        usdtVault.setStrategy(address(newStrategy));
        vm.stopPrank();

        // All capital should be back in the vault (liquid)
        assertEq(usdtVault.liquidReserve(), SEED);
        assertEq(usdtVault.deployedCapital(), 0);
    }

    // =====================================================================
    //  Access control
    // =====================================================================

    function test_Release_OnlyEngine() public {
        vm.prank(alice);
        vm.expectRevert("YieldVault: only engine");
        usdtVault.release(1 ether, alice);
    }

    function test_Rebalance_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        usdtVault.rebalance();
    }

    function test_SetStrategy_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        usdtVault.setStrategy(address(0));
    }

    function test_SetFeeRate_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        usdtVault.setFeeRate(50);
    }

    function test_SetFeeRate_MaxCap() public {
        vm.prank(owner);
        vm.expectRevert("YieldVault: fee too high");
        usdtVault.setFeeRate(1_001);
    }

    // =====================================================================
    //  Coverage ratio view
    // =====================================================================

    function test_CoverageRatio_FullyLiquid() public view {
        // No strategy deployed yet → 100 % liquid
        assertEq(usdtVault.currentCoverageRatio(), 10_000);
    }

    function test_CoverageRatio_AfterRebalance() public {
        vm.prank(owner);
        usdtVault.rebalance();
        assertEq(usdtVault.currentCoverageRatio(), COVERAGE_RATIO);
    }

    // =====================================================================
    //  getPoolBalance returns total (liquid + deployed)
    // =====================================================================

    function test_GetPoolBalance_IncludesDeployed() public {
        vm.prank(owner);
        usdtVault.rebalance();

        assertEq(usdtVault.getPoolBalance(), SEED);
        assertEq(usdtVault.liquidReserve(), 200_000 ether);
        assertEq(usdtVault.deployedCapital(), 800_000 ether);
    }
}
