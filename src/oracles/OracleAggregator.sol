// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IOraklFeed.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 @title OracleAggregator
 @notice Dual-oracle price feed aggregator: Orakl (primary, push) + Pyth (fallback, pull).
         Provides cross-validation when both feeds are available and automatic fallback.
*/
contract OracleAggregator is Ownable {
    // ── Constants ──────────────────────────────────────────────────────────────
    uint256 public constant MAX_DEVIATION_BPS = 500; // 5 %
    uint256 public constant DEFAULT_MAX_STALENESS = 120; // seconds

    // ── Immutables ─────────────────────────────────────────────────────────────
    IOraklFeed public immutable oraklFeed;
    IPyth      public immutable pyth;
    bytes32    public immutable pythPriceId;
    uint8      public immutable oraklDecimals;

    /// @notice true when the Pyth pair is quoted as USD/TOKEN (e.g. USD/MYR)
    ///         and needs to be inverted to match Orakl's TOKEN/USD convention.
    bool      public immutable pythNeedsInvert;

    // ── Mutable config ─────────────────────────────────────────────────────────
    uint256 public deviationThresholdBps; // e.g. 300 = 3 %
    bool    public crossValidationEnabled;
    uint256 public maxStaleness;

    // ── Events ─────────────────────────────────────────────────────────────────
    event DeviationThresholdUpdated(uint256 oldBps, uint256 newBps);
    event CrossValidationToggled(bool enabled);
    event OracleMode(string mode); // "orakl_primary" | "pyth_fallback" | "cross_validated"

    // ── Constructor ─────────────────────────────────────────────────────────────
    /**
     * @param oraklFeed_           Orakl aggregator proxy (TOKEN/USD, 8-dec).
     * @param pyth_                Pyth contract on the same chain.
     * @param pythPriceId_         Pyth price feed id (bytes32).
     * @param pythNeedsInvert_     true when Pyth quote is USD/TOKEN instead of TOKEN/USD.
     * @param deviationThresholdBps_  Max allowed deviation between the two feeds (bps).
     * @param owner_               Contract owner.
     */
    constructor(
        address oraklFeed_,
        address pyth_,
        bytes32 pythPriceId_,
        bool    pythNeedsInvert_,
        uint256 deviationThresholdBps_,
        address owner_
    ) Ownable(owner_) {
        require(oraklFeed_ != address(0), "OA: zero orakl");
        require(pyth_ != address(0), "OA: zero pyth");

        oraklFeed          = IOraklFeed(oraklFeed_);
        pyth               = IPyth(pyth_);
        pythPriceId        = pythPriceId_;
        oraklDecimals      = IOraklFeed(oraklFeed_).decimals();
        pythNeedsInvert    = pythNeedsInvert_;
        deviationThresholdBps = deviationThresholdBps_;
        crossValidationEnabled = true;
        maxStaleness       = DEFAULT_MAX_STALENESS;
    }

    // ── Public view: unified price ─────────────────────────────────────────────

    /**
     * @notice Return the best-available price (8-decimal, TOKEN/USD format).
     *         1. Try Orakl (push oracle – always on-chain).
     *         2. If Orakl fails, fall back to Pyth.
     *         3. If both available & cross-validation on, check deviation.
     */
    function getPrice() external view returns (int256 price, uint8 decimals) {
        decimals = oraklDecimals; // always 8

        (bool oraklOk, int256 oraklPrice) = _getOraklPriceSafe();
        (bool pythOk,  int256 pythPrice)  = _getPythPriceSafe();

        if (oraklOk && pythOk && crossValidationEnabled) {
            _validateDeviation(oraklPrice, pythPrice);
            price = oraklPrice;
            return (price, decimals);
        }

        if (oraklOk) {
            price = oraklPrice;
            return (price, decimals);
        }

        if (pythOk) {
            price = pythPrice;
            return (price, decimals);
        }

        revert("OA: both oracles down");
    }

    /// @notice Read Orakl price directly (reverts on failure).
    function getOraklPrice() external view returns (int256 price, uint8 dec) {
        price = _getOraklPrice();
        dec   = oraklDecimals;
    }

    /// @notice Read Pyth price directly (reverts on failure).
    function getPythPrice() external view returns (int256 price, uint8 dec) {
        (price, dec) = _getPythPrice();
    }

    // ── Admin ──────────────────────────────────────────────────────────────────

    function setDeviationThreshold(uint256 bps) external onlyOwner {
        require(bps <= MAX_DEVIATION_BPS, "OA: threshold too high");
        emit DeviationThresholdUpdated(deviationThresholdBps, bps);
        deviationThresholdBps = bps;
    }

    function setCrossValidation(bool enabled) external onlyOwner {
        crossValidationEnabled = enabled;
        emit CrossValidationToggled(enabled);
    }

    function setMaxStaleness(uint256 seconds_) external onlyOwner {
        maxStaleness = seconds_;
    }

    // ── Internal ───────────────────────────────────────────────────────────────

    function _getOraklPrice() internal view returns (int256) {
        (, int256 answer,) = oraklFeed.latestRoundData();
        require(answer > 0, "OA: invalid orakl price");
        return answer;
    }

    function _getOraklPriceSafe() internal view returns (bool ok, int256 price) {
        try this._getOraklPriceExternal() returns (int256 p) {
            return (true, p);
        } catch {
            return (false, 0);
        }
    }

    /// @dev Trampoline so the try/catch works on an internal-read pattern.
    function _getOraklPriceExternal() external view returns (int256) {
        return _getOraklPrice();
    }

    function _getPythPrice() internal view returns (int256 price, uint8 dec) {
        PythStructs.Price memory p = pyth.getPriceNoOlderThan(pythPriceId, maxStaleness);
        require(p.price > 0, "OA: invalid pyth price");

        if (pythNeedsInvert) {
            // Pyth gives USD/TOKEN (e.g. USD/MYR ≈ 4.41).
            // Invert: TOKEN/USD = 10^(|expo|*2) / price
            // Example: price=441000000, expo=-8 → rate = 10^16 / 441000000 ≈ 22675737 (≈ $0.2268)
            uint256 absPrice  = uint256(uint64(p.price));
            uint256 exponent  = uint256(uint32(-p.expo)); // e.g. 8
            uint256 scale     = 10 ** (exponent * 2);     // 10^16
            price = int256(scale / absPrice);
            dec   = uint8(exponent); // 8 decimals
        } else {
            // Same direction as Orakl (TOKEN/USD, 8-dec).
            price = int256(int64(p.price));
            dec   = uint8(uint32(-p.expo));
        }
    }

    function _getPythPriceSafe() internal view returns (bool ok, int256 price) {
        try this._getPythPriceExternal() returns (int256 p, uint8) {
            return (true, p);
        } catch {
            return (false, 0);
        }
    }

    /// @dev Trampoline for try/catch.
    function _getPythPriceExternal() external view returns (int256 price, uint8 dec) {
        return _getPythPrice();
    }

    function _validateDeviation(int256 a, int256 b) internal view {
        int256 diff = a > b ? a - b : b - a;
        int256 avg  = (a + b) / 2;
        require(avg > 0, "OA: zero avg price");
        uint256 deviationBps = (uint256(diff) * 10_000) / uint256(avg);
        require(deviationBps <= deviationThresholdBps, "OA: price deviation too high");
    }
}
