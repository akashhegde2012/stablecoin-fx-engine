// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";

import "./interfaces/IFXPool.sol";

/**@title FXEngine
 @notice Stateless swap router for the single-sided FX liquidity pools.

    Swap flow                                                       
                                                                    
    1. User approves FXEngine to spend tokenIn.                    
    2. User calls swap(tokenIn, tokenOut, amountIn, minOut, to).   
    3. FXEngine fetches USD prices from each pool's Chainlink feed. 
    4. grossOut = amountIn * priceIn / priceOut                    
       (both prices share the same 8-decimal Chainlink format,     
        so the denominator cancels and precision is maintained).   
    5. fee = grossOut * outPool.feeRate() / 10_000                 
       Fee stays inside outPool, rewarding its LPs.               
    6. netOut = grossOut − fee  (≥ minAmountOut or revert)         
    7. amountIn sent to inPool; netOut released from outPool.      
*/
contract FXEngine is ReentrancyGuard, Ownable {
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

    /// @notice Pyth contract for on-chain price updates (pull oracle).
    IPyth public pyth;

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

    // Constructor
    constructor(address owner_, address pyth_) Ownable(owner_) {
        pyth = IPyth(pyth_);
    }

    // Admin

    /// @notice Update the Pyth contract address.
    function setPyth(address pyth_) external onlyOwner {
        pyth = IPyth(pyth_);
    }

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
    @notice Swap `amountIn` of `tokenIn` for at least `minAmountOut` of `tokenOut`.
    @param tokenIn       ERC-20 token being sold.
    @param tokenOut      ERC-20 token being bought.
    @param amountIn      Amount of tokenIn (18 dec).
    @param minAmountOut  Minimum acceptable output (slippage protection).
    @param to            Recipient of tokenOut.
    @return amountOut    Actual tokenOut received.
    */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "FXEngine: zero amountIn");
        require(to != address(0), "FXEngine: zero recipient");
        require(tokenIn != tokenOut, "FXEngine: same token");

        IFXPool poolIn = pools[tokenIn];
        IFXPool poolOut = pools[tokenOut];
        require(address(poolIn) != address(0), "FXEngine: no pool for tokenIn");
        require(address(poolOut) != address(0), "FXEngine: no pool for tokenOut");

        // ── Compute output amount 
        amountOut = _computeAmountOut(amountIn, poolIn, poolOut);
        require(amountOut >= minAmountOut, "FXEngine: slippage exceeded");
        require(amountOut <= poolOut.getPoolBalance(), "FXEngine: insufficient output liquidity");

        // ── Execute
        // 1. Pull tokenIn from the user into inPool
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(poolIn), amountIn);

        // 2. Release tokenOut from outPool to recipient
        poolOut.release(amountOut, to);

        // 3. Distribute platform fee
        _distributePlatformFee(poolIn, poolOut, amountIn);

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, to);
    }

    /**
    @notice Update Pyth price feeds and execute a swap in a single transaction.
            This ensures the Pyth oracle has fresh data before the swap reads prices.
    @param updateData  Encoded Pyth price update data (from Hermes).
    @param tokenIn       ERC-20 token being sold.
    @param tokenOut      ERC-20 token being bought.
    @param amountIn      Amount of tokenIn (18 dec).
    @param minAmountOut  Minimum acceptable output (slippage protection).
    @param to            Recipient of tokenOut.
    @return amountOut    Actual tokenOut received.
    */
    function swapWithPythUpdate(
        bytes[] calldata updateData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external payable nonReentrant returns (uint256 amountOut) {
        // 1. Update Pyth price feeds
        uint fee = pyth.getUpdateFee(updateData);
        require(msg.value >= fee, "FXEngine: insufficient pyth fee");
        pyth.updatePriceFeeds{value: fee}(updateData);

        // 2. Execute swap (same logic as swap())
        require(amountIn > 0, "FXEngine: zero amountIn");
        require(to != address(0), "FXEngine: zero recipient");
        require(tokenIn != tokenOut, "FXEngine: same token");

        IFXPool poolIn = pools[tokenIn];
        IFXPool poolOut = pools[tokenOut];
        require(address(poolIn) != address(0), "FXEngine: no pool for tokenIn");
        require(address(poolOut) != address(0), "FXEngine: no pool for tokenOut");

        amountOut = _computeAmountOut(amountIn, poolIn, poolOut);
        require(amountOut >= minAmountOut, "FXEngine: slippage exceeded");
        require(amountOut <= poolOut.getPoolBalance(), "FXEngine: insufficient output liquidity");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(poolIn), amountIn);
        poolOut.release(amountOut, to);

        // Distribute platform fee
        _distributePlatformFee(poolIn, poolOut, amountIn);

        // Refund excess ETH (Pyth fee)
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "FXEngine: refund failed");
        }

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, to);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
    @notice Return a price quote without executing the swap.
    @param tokenIn   ERC-20 token being sold.
    @param tokenOut  ERC-20 token being bought.
    @param amountIn  Amount of tokenIn (18 dec).
    @return amountOut Expected output after fees.
    */
    function getQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        require(tokenIn != tokenOut, "FXEngine: same token");
        IFXPool poolIn = pools[tokenIn];
        IFXPool poolOut = pools[tokenOut];
        require(address(poolIn) != address(0), "FXEngine: no pool for tokenIn");
        require(address(poolOut) != address(0), "FXEngine: no pool for tokenOut");
        amountOut = _computeAmountOut(amountIn, poolIn, poolOut);
    }

    /// @notice List all registered token addresses.
    function getRegisteredTokens() external view returns (address[] memory) {
        return registeredTokens;
    }

    /// @notice Summary info for a registered token.
    function getPoolInfo(address token)
        external
        view
        returns (
            address pool,
            address lpToken,
            uint256 balance,
            uint256 baseFee,
            uint256 maxFee,
            int256 price,
            uint8 priceDecimals
        )
    {
        IFXPool p = pools[token];
        require(address(p) != address(0), "FXEngine: no pool");
        pool = address(p);
        lpToken = p.lpToken();
        balance = p.getPoolBalance();
        baseFee = p.feeRate();
        maxFee = p.maxDynamicFeeRate();
        (price, priceDecimals) = p.getPrice();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /**
        @dev Core price calculation:
          grossOut = amountIn × priceIn / priceOut
    
          Both Chainlink feeds return prices with the same number of decimals
          (8 for USD feeds), so the 10^decimals factor cancels perfectly:
    
          grossOut [18 dec] = amountIn [18 dec]
                            × priceIn  [8 dec]
                            / priceOut [8 dec]
    
          When feeds have different decimals (unusual) we normalise first.
    
          The fee is then deducted from grossOut and left inside the outPool,
          rewarding its liquidity providers.
    */
    function _computeAmountOut(uint256 amountIn, IFXPool poolIn, IFXPool poolOut)
        internal
        view
        returns (uint256 amountOut)
    {
        (int256 priceIn, uint8 decIn) = poolIn.getPrice();
        (int256 priceOut, uint8 decOut) = poolOut.getPrice();

        uint256 uPriceIn = uint256(priceIn);
        uint256 uPriceOut = uint256(priceOut);

        uint256 grossOut;
        if (decIn == decOut) {
            // Common case (both 8-decimal Chainlink feeds): denominators cancel
            grossOut = (amountIn * uPriceIn) / uPriceOut;
        } else if (decIn > decOut) {
            // Scale priceOut up to match priceIn precision
            grossOut = (amountIn * uPriceIn) / (uPriceOut * 10 ** (decIn - decOut));
        } else {
            // Scale priceIn up to match priceOut precision
            grossOut = (amountIn * uPriceIn * 10 ** (decOut - decIn)) / uPriceOut;
        }

        // Deduct the outPool's dynamic fee; remainder stays in pool (LP reward)
        uint256 effectiveFeeRate = poolOut.getEffectiveFeeRate(grossOut);
        uint256 fee = (grossOut * effectiveFeeRate) / FEE_DENOMINATOR;
        amountOut = grossOut - fee;
    }

    /**
     * @notice Distribute platform fee from the output pool after a swap.
     *         fee = grossOut - amountOut. Platform gets fee * platformFeeBps / 10000.
     *         The remaining fee (LP share) stays in the pool implicitly.
     */
    function _distributePlatformFee(IFXPool poolIn, IFXPool poolOut, uint256 amountIn) internal {
        // Recompute grossOut to derive the fee
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

        uint256 effectiveFeeRate = poolOut.getEffectiveFeeRate(grossOut);
        uint256 totalFee = (grossOut * effectiveFeeRate) / FEE_DENOMINATOR;
        uint256 platformFee = (totalFee * poolOut.platformFeeBps()) / FEE_DENOMINATOR;

        if (platformFee > 0) {
            poolOut.releasePlatformFee(platformFee);
        }
    }
}
