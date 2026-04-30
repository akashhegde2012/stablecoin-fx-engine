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
import "../src/distribution/YieldDistributor.sol";

/// @title YieldDistributorTest
/// @notice Tests for Phase 4: fee collection, LP staking, bonus rewards,
///         and coverage-weighted APY distribution.
contract YieldDistributorTest is Test {
    // ── Constants ────────────────────────────────────────────────────────────
    int256 constant USDT_USD = 100_000_000;
    int256 constant SGD_USD = 74_190_000;

    uint256 constant FEE_RATE = 30;
    uint256 constant COVERAGE = 2_000;
    uint256 constant SEED = 1_000_000 ether;

    // ── Actors ───────────────────────────────────────────────────────────────
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    // ── Contracts ────────────────────────────────────────────────────────────
    USDTToken usdt;
    SGDToken sgd;
    MockOraklFeed usdtFeed;
    MockOraklFeed sgdFeed;

    YieldVault usdtVault;
    YieldVault sgdVault;
    MockStrategy usdtStrategy;
    MockStrategy sgdStrategy;
    FXEngine engine;
    YieldDistributor distributor;

    // ── Bonus reward mock token ──────────────────────────────────────────────
    USDTToken bonusToken; // reuse ERC-20 as a generic bonus token

    // ── Dead shares constant ─────────────────────────────────────────────────
    uint256 constant DEAD = 1000;

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

        // Strategies
        usdtStrategy = new MockStrategy(address(usdtVault), address(usdt));
        sgdStrategy = new MockStrategy(address(sgdVault), address(sgd));
        usdtVault.setStrategy(address(usdtStrategy));
        sgdVault.setStrategy(address(sgdStrategy));

        // Engine
        engine = new FXEngine(owner, address(0));
        engine.registerPool(address(usdt), address(usdtVault));
        engine.registerPool(address(sgd), address(sgdVault));
        usdtVault.proposeEngine(address(engine));
        usdtVault.acceptEngine();
        sgdVault.proposeEngine(address(engine));
        sgdVault.acceptEngine();

        // Distributor
        distributor = new YieldDistributor(owner);
        distributor.registerVault(address(usdtVault));
        distributor.registerVault(address(sgdVault));
        distributor.setFeeNotifier(address(engine), true);
        distributor.setFeeNotifier(address(usdtVault), true);
        distributor.setFeeNotifier(address(sgdVault), true);

        // Wire engine → distributor (10 % of swap fee)
        engine.setDistributor(address(distributor));
        engine.setProtocolFeeRate(1_000);

        // Wire vaults → distributor (10 % of harvest yield)
        usdtVault.setDistributor(address(distributor));
        usdtVault.setHarvestFeeRate(1_000);
        sgdVault.setDistributor(address(distributor));
        sgdVault.setHarvestFeeRate(1_000);

        // Bonus token
        bonusToken = new USDTToken(owner);

        // Mint & seed liquidity
        usdt.mint(alice, SEED + 200_000 ether);
        sgd.mint(alice, SEED + 200_000 ether);
        usdt.mint(bob, 100_000 ether);
        sgd.mint(bob, 100_000 ether);
        usdt.mint(charlie, 100_000 ether);

        vm.stopPrank();

        // Alice seeds vaults
        vm.startPrank(alice);
        usdt.approve(address(usdtVault), SEED);
        sgd.approve(address(sgdVault), SEED);
        usdtVault.deposit(SEED);
        sgdVault.deposit(SEED);
        vm.stopPrank();
    }

    // =====================================================================
    //  Deployment sanity
    // =====================================================================

    function test_DistributorDeployed() public view {
        assertEq(distributor.getVaultCount(), 2);
        assertEq(engine.distributor(), address(distributor));
        assertEq(engine.protocolFeeRate(), 1_000);
    }

    function test_VaultsRegistered() public view {
        (bool reg,,,,,,) = distributor.vaults(address(usdtVault));
        assertTrue(reg);
        (reg,,,,,,) = distributor.vaults(address(sgdVault));
        assertTrue(reg);
    }

    // =====================================================================
    //  Protocol fee collection from swaps
    // =====================================================================

    function test_ProtocolFee_CollectedOnSwap() public {
        uint256 amountIn = 1_000 ether;
        uint256 distBalBefore = usdt.balanceOf(address(distributor));

        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        engine.swap(address(usdt), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        // SGD protocol fee should be in distributor
        uint256 sgdDistBal = sgd.balanceOf(address(distributor));
        assertGt(sgdDistBal, 0);
        console.log("SGD protocol fee collected:", sgdDistBal);
    }

    function test_ProtocolFee_ZeroWhenNoDistributor() public {
        vm.prank(owner);
        engine.setDistributor(address(0));

        uint256 amountIn = 1_000 ether;
        vm.startPrank(bob);
        usdt.approve(address(engine), amountIn);
        uint256 out = engine.swap(address(usdt), address(sgd), amountIn, 0, bob);
        vm.stopPrank();

        assertGt(out, 0);
        assertEq(sgd.balanceOf(address(distributor)), 0);
    }

    // =====================================================================
    //  Harvest fee collection
    // =====================================================================

    function test_HarvestFee_CollectedOnHarvest() public {
        vm.prank(owner);
        usdtVault.rebalance();

        // Simulate yield
        vm.prank(owner);
        usdt.mint(address(usdtStrategy), 10_000 ether);

        uint256 distBalBefore = usdt.balanceOf(address(distributor));

        vm.prank(owner);
        uint256 netProfit = usdtVault.harvest();

        uint256 distBalAfter = usdt.balanceOf(address(distributor));
        uint256 harvestFee = distBalAfter - distBalBefore;

        assertGt(harvestFee, 0);
        // 10% of 10k = 1k
        assertEq(harvestFee, 1_000 ether);
        // netProfit should be 10k - 1k = 9k
        assertEq(netProfit, 9_000 ether);

        console.log("Harvest fee to distributor:", harvestFee);
        console.log("Net profit to vault:", netProfit);
    }

    // =====================================================================
    //  Staking and fee reward claiming
    // =====================================================================

    function test_StakeAndClaimFees() public {
        // Alice stakes her vault shares
        uint256 aliceShares = usdtVault.balanceOf(alice);
        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceShares);
        distributor.stake(address(usdtVault), aliceShares);
        vm.stopPrank();

        // Generate protocol fees via a swap
        vm.startPrank(bob);
        usdt.approve(address(engine), 10_000 ether);
        engine.swap(address(usdt), address(sgd), 10_000 ether, 0, bob);
        vm.stopPrank();

        // Check pending fees
        uint256 pending = distributor.pendingFees(address(sgdVault), alice);
        // Alice hasn't staked sgdVault, so sgd fees should be 0 for her in sgdVault
        assertEq(pending, 0);

        // SGD fees went to distributor but no sgdVault stakers, so they accumulate
        uint256 sgdInDist = sgd.balanceOf(address(distributor));
        assertGt(sgdInDist, 0);
    }

    function test_StakeClaimUnstake_FullCycle() public {
        uint256 aliceShares = usdtVault.balanceOf(alice);

        // Alice stakes all USDT vault shares
        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceShares);
        distributor.stake(address(usdtVault), aliceShares);
        vm.stopPrank();

        // Generate harvest fees
        vm.startPrank(owner);
        usdtVault.rebalance();
        usdt.mint(address(usdtStrategy), 10_000 ether);
        usdtVault.harvest(); // 10% = 1000 USDT to distributor
        vm.stopPrank();

        // Check and claim (allow small rounding from accFeePerShare integer division)
        uint256 pendingFee = distributor.pendingFees(address(usdtVault), alice);
        assertApproxEqAbs(pendingFee, 1_000 ether, 1e6);

        uint256 usdtBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        (uint256 feeRwd,) = distributor.claim(address(usdtVault));
        assertApproxEqAbs(feeRwd, 1_000 ether, 1e6);
        assertApproxEqAbs(usdt.balanceOf(alice), usdtBefore + 1_000 ether, 1e6);

        // Unstake
        vm.prank(alice);
        distributor.unstake(address(usdtVault), aliceShares);
        assertEq(usdtVault.balanceOf(alice), aliceShares);
    }

    // =====================================================================
    //  Multi-staker fee distribution
    // =====================================================================

    function test_MultiStaker_ProportionalFees() public {
        uint256 aliceShares = usdtVault.balanceOf(alice);

        // Bob deposits into vault first
        vm.startPrank(bob);
        usdt.approve(address(usdtVault), 50_000 ether);
        usdtVault.deposit(50_000 ether);
        uint256 bobShares = usdtVault.balanceOf(bob);
        vm.stopPrank();

        // Both stake (alice has ~95%, bob has ~5%)
        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceShares);
        distributor.stake(address(usdtVault), aliceShares);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(address(usdtVault)).approve(address(distributor), bobShares);
        distributor.stake(address(usdtVault), bobShares);
        vm.stopPrank();

        // Generate 1000 USDT in fees via harvest
        vm.startPrank(owner);
        usdtVault.rebalance();
        usdt.mint(address(usdtStrategy), 10_000 ether);
        usdtVault.harvest();
        vm.stopPrank();

        uint256 alicePending = distributor.pendingFees(address(usdtVault), alice);
        uint256 bobPending = distributor.pendingFees(address(usdtVault), bob);

        // Alice should get more than Bob (proportional to stake)
        assertGt(alicePending, bobPending);
        assertApproxEqAbs(alicePending + bobPending, 1_000 ether, 1e6);

        console.log("Alice pending fees:", alicePending);
        console.log("Bob pending fees:  ", bobPending);
    }

    // =====================================================================
    //  Bonus rewards
    // =====================================================================

    function test_BonusReward_Configuration() public {
        uint256 amount = 100_000 ether;
        uint256 duration = 30 days;

        vm.startPrank(owner);
        bonusToken.mint(owner, amount);
        bonusToken.approve(address(distributor), amount);
        distributor.configureBonusReward(address(bonusToken), amount, duration);
        vm.stopPrank();

        assertEq(address(distributor.bonusToken()), address(bonusToken));
        assertEq(distributor.bonusPerSecond(), amount / duration);
        assertEq(bonusToken.balanceOf(address(distributor)), amount);
    }

    function test_BonusReward_AccruesToStakers() public {
        // Setup bonus rewards
        uint256 bonusAmount = 100_000 ether;
        uint256 duration = 100; // 100 seconds for easy math
        vm.startPrank(owner);
        bonusToken.mint(owner, bonusAmount);
        bonusToken.approve(address(distributor), bonusAmount);
        distributor.configureBonusReward(address(bonusToken), bonusAmount, duration);
        vm.stopPrank();

        // Rebalance to set allocation points (based on coverage ratio)
        vm.startPrank(owner);
        usdtVault.rebalance();
        sgdVault.rebalance();
        distributor.updateAllocPoints();
        vm.stopPrank();

        // Alice stakes USDT vault shares
        uint256 aliceShares = usdtVault.balanceOf(alice);
        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceShares);
        distributor.stake(address(usdtVault), aliceShares);
        vm.stopPrank();

        // Advance 50 seconds (half the reward period)
        vm.warp(block.timestamp + 50);

        // Check pending bonus
        uint256 pending = distributor.pendingBonus(address(usdtVault), alice);
        assertGt(pending, 0);

        // Claim
        vm.prank(alice);
        (, uint256 bonusRwd) = distributor.claim(address(usdtVault));
        assertGt(bonusRwd, 0);
        assertEq(bonusToken.balanceOf(alice), bonusRwd);

        console.log("Bonus earned after 50s:", bonusRwd);
    }

    // =====================================================================
    //  Coverage-ratio weighted allocation
    // =====================================================================

    function test_AllocPoints_ReflectCoverageRatio() public {
        // Before rebalance: 100% liquid → allocPoint = 0
        (,,,, uint256 allocBefore,,) = distributor.vaults(address(usdtVault));
        assertEq(allocBefore, 0);

        // Rebalance: 80% deployed → allocPoint = 8000
        vm.prank(owner);
        usdtVault.rebalance();
        vm.prank(owner);
        distributor.updateAllocPoints();

        (,,,, uint256 allocAfter,,) = distributor.vaults(address(usdtVault));
        assertEq(allocAfter, 8_000);

        // Change coverage to 50%
        vm.startPrank(owner);
        usdtVault.setTargetCoverageRatio(5_000);
        usdtVault.rebalance();
        distributor.updateAllocPoints();
        vm.stopPrank();

        (,,,, uint256 allocHalf,,) = distributor.vaults(address(usdtVault));
        assertEq(allocHalf, 5_000);
    }

    function test_AllocPoints_HigherDeploymentGetsMoreBonus() public {
        // Setup bonus
        uint256 bonusAmount = 100_000 ether;
        vm.startPrank(owner);
        bonusToken.mint(owner, bonusAmount);
        bonusToken.approve(address(distributor), bonusAmount);
        distributor.configureBonusReward(address(bonusToken), bonusAmount, 100);

        // USDT vault: 80% deployed (allocPoint = 8000)
        usdtVault.rebalance();
        // SGD vault: 50% deployed (allocPoint = 5000)
        sgdVault.setTargetCoverageRatio(5_000);
        sgdVault.rebalance();
        distributor.updateAllocPoints();
        vm.stopPrank();

        // Alice stakes in USDT vault, Bob stakes in SGD vault
        uint256 aliceUSDT = usdtVault.balanceOf(alice);
        uint256 aliceSGD = sgdVault.balanceOf(alice);

        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceUSDT);
        distributor.stake(address(usdtVault), aliceUSDT);
        IERC20(address(sgdVault)).approve(address(distributor), aliceSGD);
        distributor.stake(address(sgdVault), aliceSGD);
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 50);

        uint256 usdtBonus = distributor.pendingBonus(address(usdtVault), alice);
        uint256 sgdBonus = distributor.pendingBonus(address(sgdVault), alice);

        // USDT vault (8000 alloc) should earn more bonus than SGD vault (5000 alloc)
        assertGt(usdtBonus, sgdBonus);

        console.log("USDT vault bonus (8000 alloc):", usdtBonus);
        console.log("SGD  vault bonus (5000 alloc):", sgdBonus);
    }

    // =====================================================================
    //  claimAll
    // =====================================================================

    function test_ClaimAll() public {
        // Stake in both vaults
        uint256 aliceUSDT = usdtVault.balanceOf(alice);
        uint256 aliceSGD = sgdVault.balanceOf(alice);

        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceUSDT);
        distributor.stake(address(usdtVault), aliceUSDT);
        IERC20(address(sgdVault)).approve(address(distributor), aliceSGD);
        distributor.stake(address(sgdVault), aliceSGD);
        vm.stopPrank();

        // Generate fees in both vaults
        vm.startPrank(owner);
        usdtVault.rebalance();
        sgdVault.rebalance();
        usdt.mint(address(usdtStrategy), 10_000 ether);
        sgd.mint(address(sgdStrategy), 10_000 ether);
        usdtVault.harvest();
        sgdVault.harvest();
        vm.stopPrank();

        // claimAll
        vm.prank(alice);
        (uint256 totalFees,) = distributor.claimAll();
        assertGt(totalFees, 0);
        console.log("Total fees claimed across all vaults:", totalFees);
    }

    // =====================================================================
    //  Access control
    // =====================================================================

    function test_NotifyFees_OnlyAuthorized() public {
        vm.prank(bob);
        vm.expectRevert("YD: not authorized");
        distributor.notifyFees(address(usdtVault), 1_000 ether);
    }

    function test_RegisterVault_OnlyOwner() public {
        vm.prank(bob);
        vm.expectRevert();
        distributor.registerVault(address(0x1234));
    }

    function test_Stake_RevertUnregisteredVault() public {
        vm.prank(alice);
        vm.expectRevert("YD: vault not registered");
        distributor.stake(address(0x1234), 1_000 ether);
    }

    function test_Unstake_RevertInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert("YD: insufficient stake");
        distributor.unstake(address(usdtVault), 1_000 ether);
    }

    // =====================================================================
    //  Edge cases
    // =====================================================================

    function test_FeesAccumulate_WhenNoStakers() public {
        // No one staked yet — generate swap fees
        vm.startPrank(bob);
        usdt.approve(address(engine), 10_000 ether);
        engine.swap(address(usdt), address(sgd), 10_000 ether, 0, bob);
        vm.stopPrank();

        // SGD fees sit in distributor with no stakers
        uint256 sgdFees = sgd.balanceOf(address(distributor));
        assertGt(sgdFees, 0);

        // Alice stakes SGD vault shares
        uint256 aliceSGD = sgdVault.balanceOf(alice);
        vm.startPrank(alice);
        IERC20(address(sgdVault)).approve(address(distributor), aliceSGD);
        distributor.stake(address(sgdVault), aliceSGD);
        vm.stopPrank();

        // With the undistributed-fee flush, the first staker receives
        // all fees that accumulated while there were zero stakers.
        uint256 pending = distributor.pendingFees(address(sgdVault), alice);
        assertGt(pending, 0);
        assertApproxEqAbs(pending, sgdFees, 1e6);
    }

    function test_EmergencyWithdraw_WorksWhenPaused() public {
        uint256 aliceShares = usdtVault.balanceOf(alice);
        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceShares);
        distributor.stake(address(usdtVault), aliceShares);
        vm.stopPrank();

        // Pause the distributor
        vm.prank(owner);
        distributor.pause();

        // Normal unstake should revert
        vm.prank(alice);
        vm.expectRevert();
        distributor.unstake(address(usdtVault), aliceShares);

        // Emergency withdraw should work
        vm.prank(alice);
        distributor.emergencyWithdraw(address(usdtVault));
        assertEq(usdtVault.balanceOf(alice), aliceShares);

        vm.prank(owner);
        distributor.unpause();
    }

    function test_UndistributedFees_FlushedOnFirstStake() public {
        // Generate fees with zero stakers
        vm.startPrank(owner);
        usdtVault.rebalance();
        usdt.mint(address(usdtStrategy), 10_000 ether);
        usdtVault.harvest(); // 1000 USDT fee to distributor, no stakers
        vm.stopPrank();

        uint256 undist = distributor.undistributedFees(address(usdtVault));
        assertEq(undist, 1_000 ether);

        // Alice stakes — undistributed fees should flush
        uint256 aliceShares = usdtVault.balanceOf(alice);
        vm.startPrank(alice);
        IERC20(address(usdtVault)).approve(address(distributor), aliceShares);
        distributor.stake(address(usdtVault), aliceShares);
        vm.stopPrank();

        // Undistributed should be zero now
        assertEq(distributor.undistributedFees(address(usdtVault)), 0);

        // Alice should be able to claim the flushed fees
        uint256 pending = distributor.pendingFees(address(usdtVault), alice);
        assertApproxEqAbs(pending, 1_000 ether, 1e6);
    }

    function test_BonusCarryOver_OnReconfigure() public {
        uint256 amount = 100_000 ether;
        uint256 duration = 100;

        vm.startPrank(owner);
        bonusToken.mint(owner, amount * 2);
        bonusToken.approve(address(distributor), amount * 2);
        distributor.configureBonusReward(address(bonusToken), amount, duration);
        vm.stopPrank();

        // Advance 50s (half used, half remains)
        vm.warp(block.timestamp + 50);

        uint256 remaining = (100 - 50) * distributor.bonusPerSecond();

        vm.startPrank(owner);
        distributor.configureBonusReward(address(bonusToken), amount, duration);
        vm.stopPrank();

        // New rate should include carryover: (amount + remaining) / duration
        uint256 expectedRate = (amount + remaining) / duration;
        assertEq(distributor.bonusPerSecond(), expectedRate);
    }

    function test_Swap_QuoteUnchangedByProtocolFee() public {
        // The getQuote view should return the same regardless of protocol fee
        uint256 quoteWithFee = engine.getQuote(address(usdt), address(sgd), 1_000 ether);

        vm.prank(owner);
        engine.setProtocolFeeRate(0);
        uint256 quoteNoFee = engine.getQuote(address(usdt), address(sgd), 1_000 ether);

        // Quote is the user's output — same either way
        assertEq(quoteWithFee, quoteNoFee);
    }
}
