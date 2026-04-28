// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../FXEngine.sol";
import "../interfaces/IYieldDistributor.sol";
import "./NettingLib.sol";

/**
 * @title SettlementEngine
 *  @notice Extended FX swap router that adds two capabilities on top of FXEngine:
 *
 *          1. **Multi-hop routing**
 *             Chains through intermediate pools when a direct pair doesn't exist
 *             or when a multi-leg path is more efficient.
 *             e.g.  SGD → USDT → IDRX   (path = [SGD, USDT, IDRX])
 *
 *             Only the first and last pools have physical token flow;
 *             intermediate pools are used solely for pricing + fee calculation.
 *             This is correct because the net token change on any intermediate
 *             pool from "release then receive the same amount" is zero.
 *
 *          2. **Intent-based netting**
 *             Traders submit swap intents that escrow tokens in the engine.
 *             A keeper (or anyone) calls `settleNetted()` with a batch of
 *             intent IDs for the same token pair.  Opposing flows (A→B vs B→A)
 *             are internally netted — only the NET difference is routed through
 *             pools, dramatically reducing pool drain and gas.
 *
 *          The contract inherits FXEngine, so direct `swap()` and `getQuote()`
 *          remain available for immediate atomic swaps.
 */
contract SettlementEngine is FXEngine {
    using SafeERC20 for IERC20;
    using NettingLib for *;

    // =====================================================================
    //  Constants
    // =====================================================================

    uint256 public constant MAX_PATH_LENGTH = 5;
    uint256 public constant MAX_INTENT_DURATION = 7 days;

    // =====================================================================
    //  Netting state
    // =====================================================================

    struct SwapIntent {
        address trader;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        bool settled;
        bool cancelled;
    }

    mapping(uint256 => SwapIntent) public intents;
    uint256 public nextIntentId;

    // =====================================================================
    //  Events
    // =====================================================================

    event MultiHopSwapped(
        address indexed sender,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 hops,
        address to
    );

    event IntentSubmitted(
        uint256 indexed intentId,
        address indexed trader,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    );

    event IntentCancelled(uint256 indexed intentId);

    event IntentSettled(uint256 indexed intentId, uint256 amountOut);

    event BatchSettled(uint256 batchSize, address tokenA, address tokenB, uint256 totalPoolOutflowSaved);

    // =====================================================================
    //  Constructor
    // =====================================================================

    constructor(address owner_) FXEngine(owner_) {}

    // =====================================================================
    //  Multi-hop swap
    // =====================================================================

    /**
     * @notice Swap along a multi-token path.
     *  @param path         Ordered token addresses, length ≥ 2, ≤ MAX_PATH_LENGTH.
     *  @param amountIn     Amount of path[0] to sell.
     *  @param minAmountOut Slippage guard on final output.
     *  @param to           Recipient of path[last].
     *  @return amountOut   Actual output after all hop fees.
     */
    function swapMultiHop(address[] calldata path, uint256 amountIn, uint256 minAmountOut, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        require(path.length >= 2, "SE: path too short");
        require(path.length <= MAX_PATH_LENGTH, "SE: path too long");
        require(amountIn > 0, "SE: zero amount");
        require(to != address(0), "SE: zero recipient");

        uint256 lastHopFee;
        (amountOut, lastHopFee) = _computeMultiHopOutput(path, amountIn);
        require(amountOut >= minAmountOut, "SE: slippage exceeded");

        IFXPool lastPool = pools[path[path.length - 1]];

        uint256 pFee;
        if (distributor != address(0) && protocolFeeRate > 0) {
            pFee = (lastHopFee * protocolFeeRate) / FEE_DENOMINATOR;
        }

        uint256 totalRelease = amountOut + pFee;
        require(totalRelease <= lastPool.getPoolBalance(), "SE: insufficient output liquidity");

        IERC20(path[0]).safeTransferFrom(msg.sender, address(pools[path[0]]), amountIn);
        lastPool.release(amountOut, to);

        if (pFee > 0) {
            lastPool.release(pFee, distributor);
            IYieldDistributor(distributor).notifyFees(address(lastPool), pFee);
        }

        emit MultiHopSwapped(msg.sender, path[0], path[path.length - 1], amountIn, amountOut, path.length - 1, to);
    }

    /// @notice Quote for a multi-hop swap without execution.
    function getMultiHopQuote(address[] calldata path, uint256 amountIn) external view returns (uint256 amountOut) {
        require(path.length >= 2, "SE: path too short");
        (amountOut,) = _computeMultiHopOutput(path, amountIn);
    }

    // =====================================================================
    //  Intent submission
    // =====================================================================

    /**
     * @notice Submit a swap intent. Tokens are escrowed in the engine until
     *          settlement or cancellation.
     *  @param tokenIn      Token to sell.
     *  @param tokenOut     Token to buy.
     *  @param amountIn     Amount of tokenIn.
     *  @param minAmountOut Minimum acceptable output.
     *  @param deadline     Unix timestamp after which the intent expires.
     *  @return intentId    Unique identifier for the intent.
     */
    function submitIntent(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint256 deadline)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 intentId)
    {
        require(amountIn > 0, "SE: zero amount");
        require(tokenIn != tokenOut, "SE: same token");
        require(deadline > block.timestamp, "SE: past deadline");
        require(deadline <= block.timestamp + MAX_INTENT_DURATION, "SE: deadline too far");
        require(address(pools[tokenIn]) != address(0), "SE: no pool for tokenIn");
        require(address(pools[tokenOut]) != address(0), "SE: no pool for tokenOut");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        intentId = nextIntentId++;
        intents[intentId] = SwapIntent({
            trader: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            deadline: deadline,
            settled: false,
            cancelled: false
        });

        emit IntentSubmitted(intentId, msg.sender, tokenIn, tokenOut, amountIn, minAmountOut, deadline);
    }

    /// @notice Cancel an unsettled intent and reclaim escrowed tokens.
    function cancelIntent(uint256 intentId) external nonReentrant {
        SwapIntent storage intent = intents[intentId];
        require(msg.sender == intent.trader, "SE: not intent owner");
        require(!intent.settled, "SE: already settled");
        require(!intent.cancelled, "SE: already cancelled");

        intent.cancelled = true;
        IERC20(intent.tokenIn).safeTransfer(intent.trader, intent.amountIn);

        emit IntentCancelled(intentId);
    }

    // =====================================================================
    //  Netted batch settlement
    // =====================================================================

    /**
     * @notice Settle a batch of intents for the **same token pair** with
     *          bilateral netting.
     *
     *          Algorithm
     *          ─────────
     *          1. Validate all intents (same pair, not settled/cancelled/expired).
     *          2. Compute each intent's output using the normal _computeAmountOut
     *             pricing (identical to what a direct swap would give).
     *          3. Aggregate token flows — how much the engine holds vs. owes.
     *          4. Execute only the NET difference through pools:
     *             • surplus tokens → sent to pool (increases LP share value)
     *             • deficit tokens → released from pool
     *          5. Distribute outputs to each trader.
     *
     *          The pool balance outcomes are identical to executing every intent
     *          as an individual swap. The benefit is reduced pool drain
     *          (fewer tokens leave / enter each pool) and lower gas.
     *
     *  @param intentIds  Array of intent IDs to settle as a batch.
     */
    function settleNetted(uint256[] calldata intentIds) external nonReentrant whenNotPaused {
        require(intentIds.length > 0, "SE: empty batch");

        // ── 1. Validate & identify token pair ───────────────────────────
        (address tokenA, address tokenB) = _validateBatch(intentIds);

        // ── 2. Compute individual outputs & aggregate ───────────────────
        uint256 totalAIn;
        uint256 totalBIn;
        uint256 totalAOut;
        uint256 totalBOut;
        uint256[] memory outputs = new uint256[](intentIds.length);

        for (uint256 i = 0; i < intentIds.length; i++) {
            SwapIntent storage intent = intents[intentIds[i]];

            (uint256 output,) = _computeAmountOut(intent.amountIn, pools[intent.tokenIn], pools[intent.tokenOut]);
            require(output >= intent.minAmountOut, "SE: below min output");

            outputs[i] = output;
            intent.settled = true;

            if (intent.tokenIn == tokenA) {
                totalAIn += intent.amountIn;
                totalBOut += output;
            } else {
                totalBIn += intent.amountIn;
                totalAOut += output;
            }
        }

        // ── 3. Compute net pool flows ───────────────────────────────────
        NettingLib.FlowResult memory flows = NettingLib.computeNetFlows(totalAIn, totalBIn, totalAOut, totalBOut);

        // ── 4. Execute net flows ────────────────────────────────────────
        _executeFlows(tokenA, tokenB, flows);

        // ── 5. Distribute outputs to traders ────────────────────────────
        for (uint256 i = 0; i < intentIds.length; i++) {
            SwapIntent storage intent = intents[intentIds[i]];
            IERC20(intent.tokenOut).safeTransfer(intent.trader, outputs[i]);
            emit IntentSettled(intentIds[i], outputs[i]);
        }

        uint256 saved = NettingLib.nettingSaved(totalAOut, totalBOut, flows);
        emit BatchSettled(intentIds.length, tokenA, tokenB, saved);
    }

    // =====================================================================
    //  Views
    // =====================================================================

    /// @notice Read an intent's full details.
    function getIntent(uint256 intentId)
        external
        view
        returns (
            address trader,
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 minAmountOut,
            uint256 deadline,
            bool settled,
            bool cancelled
        )
    {
        SwapIntent storage i = intents[intentId];
        return (i.trader, i.tokenIn, i.tokenOut, i.amountIn, i.minAmountOut, i.deadline, i.settled, i.cancelled);
    }

    // =====================================================================
    //  Internal helpers
    // =====================================================================

    function _computeMultiHopOutput(address[] calldata path, uint256 amountIn)
        internal
        view
        returns (uint256 amountOut, uint256 lastHopFee)
    {
        amountOut = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            IFXPool poolIn = pools[path[i]];
            IFXPool poolOut = pools[path[i + 1]];
            require(address(poolIn) != address(0), "SE: no pool in path");
            require(address(poolOut) != address(0), "SE: no pool in path");
            uint256 fee;
            (amountOut, fee) = _computeAmountOut(amountOut, poolIn, poolOut);
            if (i == path.length - 2) lastHopFee = fee;
        }
    }

    /// @dev Validate that all intents in the batch are active, unexpired,
    ///      and belong to the same canonical token pair.
    function _validateBatch(uint256[] calldata intentIds) internal view returns (address tokenA, address tokenB) {
        SwapIntent storage first = intents[intentIds[0]];
        _requireActive(first);

        tokenA = first.tokenIn < first.tokenOut ? first.tokenIn : first.tokenOut;
        tokenB = first.tokenIn < first.tokenOut ? first.tokenOut : first.tokenIn;

        for (uint256 i = 1; i < intentIds.length; i++) {
            SwapIntent storage intent = intents[intentIds[i]];
            _requireActive(intent);

            address a = intent.tokenIn < intent.tokenOut ? intent.tokenIn : intent.tokenOut;
            address b = intent.tokenIn < intent.tokenOut ? intent.tokenOut : intent.tokenIn;
            require(a == tokenA && b == tokenB, "SE: mixed token pairs");
        }
    }

    function _requireActive(SwapIntent storage intent) internal view {
        require(intent.trader != address(0), "SE: intent does not exist");
        require(!intent.settled, "SE: already settled");
        require(!intent.cancelled, "SE: already cancelled");
        require(intent.deadline >= block.timestamp, "SE: expired");
    }

    /// @dev Execute the net token flows between engine and pools.
    function _executeFlows(address tokenA, address tokenB, NettingLib.FlowResult memory flows) internal {
        if (flows.surplusA > 0) {
            IERC20(tokenA).safeTransfer(address(pools[tokenA]), flows.surplusA);
        }
        if (flows.deficitA > 0) {
            pools[tokenA].release(flows.deficitA, address(this));
        }

        if (flows.surplusB > 0) {
            IERC20(tokenB).safeTransfer(address(pools[tokenB]), flows.surplusB);
        }
        if (flows.deficitB > 0) {
            pools[tokenB].release(flows.deficitB, address(this));
        }
    }
}
