// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IFXPool.sol";
import "./interfaces/IYieldDistributor.sol";

/**
 * @title FXEngine
 *  @notice Stateless swap router for the single-sided FX liquidity pools.
 *
 *     Swap flow                                                       
 *
 *     1. User approves FXEngine to spend tokenIn.                    
 *     2. User calls swap(tokenIn, tokenOut, amountIn, minOut, to).   
 *     3. FXEngine fetches USD prices from each pool's Chainlink feed. 
 *     4. grossOut = amountIn * priceIn / priceOut                    
 *        (both prices share the same 8-decimal Chainlink format,     
 *         so the denominator cancels and precision is maintained).   
 *     5. fee = grossOut * outPool.feeRate() / 10_000                 
 *        Fee stays inside outPool, rewarding its LPs.               
 *     6. netOut = grossOut − fee  (≥ minAmountOut or revert)         
 *     7. amountIn sent to inPool; netOut released from outPool.
 */
contract FXEngine is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    uint256 public constant FEE_DENOMINATOR = 10_000;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Maps a stablecoin token address to its FXPool.
    mapping(address => IFXPool) public pools;

    /// @notice Ordered list of registered token addresses for enumeration.
    address[] public registeredTokens;

    /// @notice YieldDistributor that receives protocol fees.
    address public distributor;

    /// @notice Protocol fee rate in bps — fraction of the pool's swap fee
    ///         redirected to the distributor (e.g. 1000 = 10 % of pool fee).
    uint256 public protocolFeeRate;

    uint256 public constant MAX_PROTOCOL_FEE_RATE = 5_000; // 50 % of pool fee

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event PoolRegistered(address indexed token, address indexed pool);
    event PoolRemoved(address indexed token);
    event Swapped(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address to
    );
    event ProtocolFeeCollected(address indexed token, uint256 amount);
    event DistributorUpdated(address indexed oldDist, address indexed newDist);
    event ProtocolFeeRateUpdated(uint256 oldRate, uint256 newRate);

    // Constructor
    constructor(address owner_) Ownable(owner_) {}

    // Admin

    /// @notice Register a pool for a token. Overwrites any existing pool.
    /// @dev    Also authorises this engine inside the pool via FXPool.setFXEngine().
    function registerPool(address token, address pool) external onlyOwner {
        require(token != address(0), "FXEngine: zero token");
        require(pool != address(0), "FXEngine: zero pool");

        if (address(pools[token]) == address(0)) {
            registeredTokens.push(token);
        }
        pools[token] = IFXPool(pool);
        emit PoolRegistered(token, pool);
    }

    /// @notice Remove a pool registration. Does not affect pool funds.
    function removePool(address token) external onlyOwner {
        require(address(pools[token]) != address(0), "FXEngine: pool not found");
        delete pools[token];

        // Remove from the ordered list
        uint256 len = registeredTokens.length;
        for (uint256 i = 0; i < len; ++i) {
            if (registeredTokens[i] == token) {
                registeredTokens[i] = registeredTokens[len - 1];
                registeredTokens.pop();
                break;
            }
        }
        emit PoolRemoved(token);
    }

    // -------------------------------------------------------------------------
    // Core swap
    // -------------------------------------------------------------------------

    /**
     * @notice Swap `amountIn` of `tokenIn` for at least `minAmountOut` of `tokenOut`.
     * @param tokenIn       ERC-20 token being sold.
     * @param tokenOut      ERC-20 token being bought.
     * @param amountIn      Amount of tokenIn (18 dec).
     * @param minAmountOut  Minimum acceptable output (slippage protection).
     * @param to            Recipient of tokenOut.
     * @return amountOut    Actual tokenOut received.
     */
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address to)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "FXEngine: zero amountIn");
        require(to != address(0), "FXEngine: zero recipient");
        require(tokenIn != tokenOut, "FXEngine: same token");

        IFXPool poolIn = pools[tokenIn];
        IFXPool poolOut = pools[tokenOut];
        require(address(poolIn) != address(0), "FXEngine: no pool for tokenIn");
        require(address(poolOut) != address(0), "FXEngine: no pool for tokenOut");

        // ── Compute output amount + fee
        uint256 fee;
        (amountOut, fee) = _computeAmountOut(amountIn, poolIn, poolOut);
        require(amountOut >= minAmountOut, "FXEngine: slippage exceeded");

        // ── Protocol fee (fraction of pool fee sent to distributor)
        uint256 pFee;
        if (distributor != address(0) && protocolFeeRate > 0) {
            pFee = (fee * protocolFeeRate) / FEE_DENOMINATOR;
        }

        uint256 totalRelease = amountOut + pFee;
        require(totalRelease <= poolOut.getPoolBalance(), "FXEngine: insufficient output liquidity");

        // ── Execute
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(poolIn), amountIn);
        poolOut.release(amountOut, to);

        if (pFee > 0) {
            poolOut.release(pFee, distributor);
            IYieldDistributor(distributor).notifyFees(address(poolOut), pFee);
            emit ProtocolFeeCollected(tokenOut, pFee);
        }

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, to);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Return a price quote without executing the swap.
     * @param tokenIn   ERC-20 token being sold.
     * @param tokenOut  ERC-20 token being bought.
     * @param amountIn  Amount of tokenIn (18 dec).
     * @return amountOut Expected output after fees.
     */
    function getQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "FXEngine: same token");
        IFXPool poolIn = pools[tokenIn];
        IFXPool poolOut = pools[tokenOut];
        require(address(poolIn) != address(0), "FXEngine: no pool for tokenIn");
        require(address(poolOut) != address(0), "FXEngine: no pool for tokenOut");
        (amountOut,) = _computeAmountOut(amountIn, poolIn, poolOut);
    }

    /// @notice List all registered token addresses.
    function getRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setDistributor(address dist_) external onlyOwner {
        emit DistributorUpdated(distributor, dist_);
        distributor = dist_;
    }

    function setProtocolFeeRate(uint256 rate_) external onlyOwner {
        require(rate_ <= MAX_PROTOCOL_FEE_RATE, "FXEngine: protocol fee too high");
        emit ProtocolFeeRateUpdated(protocolFeeRate, rate_);
        protocolFeeRate = rate_;
    }

    /// @notice Summary info for a registered token.
    function getPoolInfo(address token)
        external
        view
        returns (address pool, address lpToken, uint256 balance, uint256 fee, int256 price, uint8 priceDecimals)
    {
        IFXPool p = pools[token];
        require(address(p) != address(0), "FXEngine: no pool");
        pool = address(p);
        lpToken = p.lpToken();
        balance = p.getPoolBalance();
        fee = p.feeRate();
        (price, priceDecimals) = p.getPrice();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
     * @dev Core price calculation:
     *       grossOut = amountIn × priceIn / priceOut
     *
     *       Both Chainlink feeds return prices with the same number of decimals
     *       (8 for USD feeds), so the 10^decimals factor cancels perfectly:
     *
     *       grossOut [18 dec] = amountIn [18 dec]
     *                         × priceIn  [8 dec]
     *                         / priceOut [8 dec]
     *
     *       When feeds have different decimals (unusual) we normalise first.
     *
     *       The fee is then deducted from grossOut and left inside the outPool,
     *       rewarding its liquidity providers.
     */
    function _computeAmountOut(uint256 amountIn, IFXPool poolIn, IFXPool poolOut)
        internal
        view
        returns (uint256 amountOut, uint256 fee)
    {
        (int256 priceIn, uint8 decIn) = poolIn.getPrice();
        (int256 priceOut, uint8 decOut) = poolOut.getPrice();

        uint256 uPriceIn = uint256(priceIn);
        uint256 uPriceOut = uint256(priceOut);

        uint256 grossOut;
        if (decIn == decOut) {
            grossOut = (amountIn * uPriceIn) / uPriceOut;
        } else if (decIn > decOut) {
            grossOut = (amountIn * uPriceIn) / (uPriceOut * 10 ** (decIn - decOut));
        } else {
            grossOut = (amountIn * uPriceIn * 10 ** (decOut - decIn)) / uPriceOut;
        }

        fee = (grossOut * poolOut.feeRate()) / FEE_DENOMINATOR;
        amountOut = grossOut - fee;
    }
}
