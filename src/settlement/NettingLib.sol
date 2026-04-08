// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NettingLib
 *  @notice Pure helpers for computing net bilateral token flows.
 *
 *          Given a batch of opposing swap intents between two tokens (A ⇄ B),
 *          the library determines how much each token must flow to/from pools
 *          after internal netting has been applied.
 *
 *          ┌───────────────────────────────────────────────────────────┐
 *          │  A→B traders deposit totalAIn of token A into the engine │
 *          │  B→A traders deposit totalBIn of token B into the engine │
 *          │                                                           │
 *          │  Engine must deliver:                                     │
 *          │    totalAOut of A  (to B→A traders)                       │
 *          │    totalBOut of B  (to A→B traders)                       │
 *          │                                                           │
 *          │  Net token A flow = totalAIn − totalAOut                  │
 *          │    positive ⇒ surplus → send to poolA (LP value ↑)       │
 *          │    negative ⇒ deficit → release from poolA               │
 *          │  Same for token B.                                        │
 *          └───────────────────────────────────────────────────────────┘
 */
library NettingLib {
    struct FlowResult {
        uint256 surplusA;
        uint256 deficitA;
        uint256 surplusB;
        uint256 deficitB;
    }

    /// @notice Compute net pool flows after bilateral netting.
    /// @dev    For each token exactly one of surplus/deficit is non-zero.
    function computeNetFlows(uint256 totalAIn, uint256 totalBIn, uint256 totalAOut, uint256 totalBOut)
        internal
        pure
        returns (FlowResult memory r)
    {
        if (totalAIn > totalAOut) {
            r.surplusA = totalAIn - totalAOut;
        } else {
            r.deficitA = totalAOut - totalAIn;
        }

        if (totalBIn > totalBOut) {
            r.surplusB = totalBIn - totalBOut;
        } else {
            r.deficitB = totalBOut - totalBIn;
        }
    }

    /// @notice How many individual swap-equivalent pool interactions were avoided.
    /// @return saved  Sum of internally-netted volumes
    ///                (totalAOut + totalBOut) − (deficitA + deficitB).
    function nettingSaved(uint256 totalAOut, uint256 totalBOut, FlowResult memory r)
        internal
        pure
        returns (uint256 saved)
    {
        uint256 withoutNetting = totalAOut + totalBOut;
        uint256 withNetting = r.deficitA + r.deficitB;
        saved = withoutNetting > withNetting ? withoutNetting - withNetting : 0;
    }
}
