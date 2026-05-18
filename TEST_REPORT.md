# Test Report: Stablecoin FX Engine

Report date: 2026-05-16  
Repository: `stablecoin-fx-engine-coverage-improvements-tests`  
Scope reviewed: Solidity smart contracts, Foundry tests, Next.js frontend, Vitest tests, and CI configuration.

## 1. Executive Summary

The repository contains a broad automated test suite for an on-chain stablecoin FX engine and its frontend application. The test code covers the core swap engine, single-sided liquidity pools, oracle aggregation, dynamic and platform fees, ERC-4626 yield vaults, strategy adapters, intent-based settlement, netting, fee distribution, staking rewards, frontend server actions, wallet-driven UI flows, and reusable UI primitives.

Current test inventory and externally supplied execution results:

| Layer | Framework | Test files | Test cases identified | Execution result |
|---|---:|---:|---:|---|
| Smart contracts | Foundry | 5 | 178 | 178 passed, 0 failed, 0 skipped, based on colleague-provided test output |
| Frontend | Vitest + Testing Library | 16 | 50 | 50 passed, 0 failed, based on colleague-provided test output |
| Total | Mixed | 21 | 228 | 228 passed, 0 failed, based on supplied test evidence |

Important note: `README.md` states that the Foundry suite has 111 tests across 5 suites. The current Solidity test source contains 178 `function test...` cases. The report therefore treats the source code count as the current inventory and flags the README number as stale.

## 2. Test Execution Results

### 2.1 Supplied Smart Contract Test Result

The supplied Foundry output shows all contract tests passing:

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `FXEngineTest` | 56 | 0 | 0 |
| `SettlementEngineTest` | 29 | 0 | 0 |
| `StrategyAdaptersTest` | 29 | 0 | 0 |
| `YieldDistributorTest` | 30 | 0 | 0 |
| `YieldVaultTest` | 34 | 0 | 0 |
| Total | 178 | 0 | 0 |

The Foundry summary also reports: 5 test suites run, 178 tests passed, 0 failed, 0 skipped, 178 total tests.

### 2.2 Supplied Frontend Test Result

The supplied Vitest output shows all frontend tests passing:

| Metric | Result |
|---|---:|
| Test files | 16 passed / 16 total |
| Tests | 50 passed / 50 total |
| Start time | 13:12:21 |
| Duration | 2.45s |
| Vitest version shown | v4.1.6 |

The passing files shown in the output include server actions, Pyth helpers, shared UI primitives, faucet, token selector, intents, swap, liquidity, wagmi config, pools, button, header, utilities, viem client, and pools grid tests.

### 2.3 Coverage Results

#### 2.3.1 Smart Contract Coverage

The supplied Foundry coverage output reports:

| Metric | Total coverage |
|---|---:|
| Lines | 96.51% (801/830) |
| Statements | 96.47% (820/850) |
| Branches | 24.24% (72/297) |
| Functions | 95.89% (140/146) |

Per-contract coverage:

| File | Lines | Statements | Branches | Functions |
|---|---:|---:|---:|---:|
| `src/FXEngine.sol` | 97.80% | 96.70% | 27.50% | 100.00% |
| `src/distribution/YieldDistributor.sol` | 95.43% | 96.02% | 27.91% | 95.45% |
| `src/oracles/OracleAggregator.sol` | 94.67% | 95.52% | 39.13% | 92.86% |
| `src/pools/FXPool.sol` | 92.52% | 93.00% | 10.91% | 90.48% |
| `src/pools/LPToken.sol` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/settlement/NettingLib.sol` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/settlement/SettlementEngine.sol` | 100.00% | 100.00% | 20.34% | 100.00% |
| `src/strategies/AaveStrategy.sol` | 100.00% | 100.00% | 14.29% | 100.00% |
| `src/strategies/BaseStrategy.sol` | 100.00% | 100.00% | 14.29% | 100.00% |
| `src/strategies/MorphoStrategy.sol` | 100.00% | 100.00% | 20.00% | 100.00% |
| `src/strategies/PendleStrategy.sol` | 100.00% | 95.65% | 20.00% | 100.00% |
| `src/tokens/StablecoinToken.sol` | 100.00% | 100.00% | 100.00% | 100.00% |
| `src/vaults/YieldVault.sol` | 95.33% | 95.24% | 28.57% | 94.44% |

Interpretation: line, statement, and function coverage are high across the contract system. Branch coverage is materially lower, especially in pool, strategy, settlement, and distributor contracts. This is a common pattern in Solidity coverage reports when compound conditions, modifiers, and revert branches are counted aggressively, but it remains the most important metric to improve next.

#### 2.3.2 Frontend Coverage

The supplied Vitest/V8 coverage output reports:

| Metric | Total coverage |
|---|---:|
| Statements | 89.63% |
| Branches | 80.76% |
| Functions | 89.01% |
| Lines | 93.14% |

Selected frontend coverage details:

| Area/File | Statements | Branches | Functions | Lines | Notable uncovered lines |
|---|---:|---:|---:|---:|---|
| `app/actions` | 95.06% | 70.83% | 100.00% | 95.06% | Mixed branch gaps |
| `app/actions/faucet.ts` | 100.00% | 83.33% | 100.00% | 100.00% | line 70 |
| `app/actions/pools.ts` | 94.59% | 62.50% | 100.00% | 94.59% | lines 51, 100 |
| `app/actions/quote.ts` | 92.00% | 70.00% | 100.00% | 92.00% | lines 78, 94 |
| `components` | 84.72% | 81.81% | 82.45% | 89.86% | Mixed component gaps |
| `FaucetCard.tsx` | 95.83% | 84.21% | 100.00% | 100.00% | lines 28, 37-38 |
| `Header.tsx` | 100.00% | 100.00% | 100.00% | 100.00% | none |
| `IntentsPanel.tsx` | 82.66% | 75.00% | 78.94% | 91.66% | lines 170, 205-209, 233-243 |
| `LiquidityPanel.tsx` | 96.49% | 88.37% | 81.81% | 95.23% | lines 217, 267 |
| `PoolsGrid.tsx` | 100.00% | 50.00% | 100.00% | 100.00% | line 41 |
| `SwapCard.tsx` | 75.23% | 83.13% | 71.42% | 82.22% | lines 133-134, 161-166, 170-173, 177-179, 236 |
| `TokenSelector.tsx` | 100.00% | 100.00% | 100.00% | 100.00% | none |
| `components/ui` | 100.00% | 85.71% | 100.00% | 100.00% | `button.tsx` line 46 |
| `lib` | 100.00% | 76.19% | 100.00% | 100.00% | `viemClient.ts` lines 25-32 |

Interpretation: frontend line coverage is strong overall. The largest component-level opportunity is `SwapCard.tsx`, which has the lowest statement/function coverage among the listed components. Branch coverage gaps remain in pool/action fallback paths, `PoolsGrid.tsx`, and `viemClient.ts`.

## 3. Test Environment and Configuration

### 3.1 Smart Contract Test Configuration

Foundry is configured in `foundry.toml` with:

| Setting | Value |
|---|---|
| Solidity source directory | `src` |
| Output directory | `out` |
| Libraries | `lib` |
| `via_ir` | `true` |
| Optimizer | enabled |
| Optimizer runs | `200` |
| Remappings | OpenZeppelin, Chainlink, Orakl, Pyth SDK |
| RPC endpoints | local Anvil and Kaia Kairos |

The repository includes the expected library folders under `lib`, including `forge-std`, `openzeppelin-contracts`, `chainlink-brownie-contracts`, `orakl`, and `pyth-sdk-solidity`.

### 3.2 Frontend Test Configuration

Frontend tests are configured in `app/vitest.config.ts`:

| Setting | Value |
|---|---|
| Test runner | Vitest |
| React plugin | `@vitejs/plugin-react` |
| DOM environment | `jsdom` |
| Global APIs | enabled |
| Setup file | `src/test/setup.ts` |
| Coverage provider | V8 |
| Coverage reporters | text, JSON summary, HTML |
| Coverage include | `src/**/*.{ts,tsx}` |
| Coverage excludes | tests, test setup, root layout/page, providers |

The setup file configures deterministic local-chain environment variables and polyfills pointer/scroll methods needed by UI component tests.

### 3.3 CI Configuration

The GitHub Actions workflow `.github/workflows/test.yml` currently validates only the Foundry project:

1. Checkout with recursive submodules.
2. Install Foundry.
3. Print Forge version.
4. Run `forge fmt --check`.
5. Run `forge build --sizes`.
6. Run `forge test -vvv`.

The workflow does not currently run the frontend Vitest suite, frontend type checking, frontend build, or frontend coverage.

## 4. Smart Contract Test Inventory

| Test suite | File | Cases | Main coverage areas |
|---|---|---:|---|
| FX engine | `test/FXEngine.t.sol` | 56 | Token setup, pool registration, oracle aggregation, quotes, swaps, LP operations, dynamic fees, platform fees, pausing, access control, input validation |
| Yield vault | `test/YieldVault.t.sol` | 34 | ERC-4626 deposits/redeems, IFXPool compatibility, strategy deployment/recall, harvests, coverage ratio, liquidity recall, admin bounds, pausing |
| Settlement engine | `test/SettlementEngine.t.sol` | 29 | Direct swaps, multi-hop quotes/swaps, intent submission/cancelation, single settlement, netted settlement, expiry, duplicate settlement prevention, NettingLib behavior |
| Strategy adapters | `test/StrategyAdapters.t.sol` | 29 | Aave, Pendle, Morpho adapter deposit/withdraw/harvest behavior, slippage failures, only-vault gating, hot swaps, multi-harvest |
| Yield distributor | `test/YieldDistributor.t.sol` | 30 | Vault registration, protocol fees, harvest fees, staking, unstaking, bonus rewards, coverage-weighted allocation, emergency withdraw, undistributed fee buffering |
| Total |  | 178 |  |

## 5. Smart Contract Coverage Assessment

### 5.1 FX Engine and Pools

The FX engine tests exercise:

- Initial pool seeding and LP token minting.
- Pool registration and removal.
- Stablecoin mint, burn, decimals, and owner behavior.
- Oracle price reads for MYR, SGD, IDRX, and USDT.
- Orakl-first and Pyth-fallback oracle behavior.
- Oracle failure handling when both sources are unavailable.
- Cross-oracle deviation rejection.
- Direct Pyth reads and inverted FX price handling.
- Quote generation across MYR/SGD, USDT/IDRX, and IDRX/USDT routes.
- Swap execution for several token pairs.
- Slippage rejection and insufficient-liquidity rejection.
- LP deposit and proportional withdrawal behavior.
- Fee accrual to output pools.
- Dynamic fee behavior for small, large, and capped trades.
- Platform fee splitting and treasury token accounting.
- Owner-only setters and maximum-bound enforcement.
- Two-step engine replacement.
- Pausable behavior on pool entry points.

This is strong coverage for the core swap and pool accounting model. The tests include positive flows, negative flows, authorization failures, boundary validation, and fee-accounting branches.

### 5.2 Oracle Aggregation

Oracle tests cover:

- Constructor validation.
- Valid Orakl prices.
- Pyth fallback when Orakl is unavailable.
- Revert behavior when both sources are down.
- Deviation checks between oracle sources.
- Admin setter bounds.
- Price normalization for mismatched oracle decimals.

The oracle test scope is appropriate for the risk profile of an FX system because quote correctness depends directly on price freshness, decimals, and cross-source consistency.

### 5.3 Yield Vault

Yield vault tests cover:

- Vault deployment and initial seeding.
- ERC-4626 share minting and redemption.
- Compatibility with the pool interface used by the swap engine.
- Strategy deployment during rebalance.
- Strategy recall when liquid funds fall below target.
- Harvest behavior and share-value increase.
- Distributor fee branch on harvest.
- Swap execution through yield-enabled vaults.
- Release behavior with strategy recall.
- Strategy replacement and approval cleanup.
- Zero-strategy and zero-asset branches.
- Owner-only administrative operations.
- Fee-rate caps.
- Coverage ratio views and target updates.
- Pausing of ERC-4626 and pool-compatible entry points.

The suite provides good coverage of liquidity management and strategy integration risks. It specifically tests the vault as both a yield product and a drop-in pool for the FX engine.

### 5.4 Settlement and Netting

Settlement tests cover:

- Direct swap compatibility.
- Two-hop, three-hop, and four-token multi-hop paths.
- Multi-hop quote equivalence to chained direct quotes.
- Slippage protection.
- Invalid path and missing-pool reverts.
- Protocol fee branch for multi-hop swaps.
- Intent submission validation.
- Intent cancelation and ownership checks.
- Single-intent settlement equivalence to direct swaps.
- Netted settlement for opposing flows.
- Pool-drain reduction through netting.
- Same-direction settlement without netting.
- Reversed-pair handling.
- Minimum-output protection.
- Expired, mixed-pair, inactive, empty, and double-settlement branches.
- Pure NettingLib flow-direction and saved-liquidity bounds.

This is one of the stronger suites in the repository because it tests both user-facing settlement behavior and the pure netting calculations that support it.

### 5.5 Strategy Adapters

Strategy adapter tests cover:

- Aave deployment, rebalance, harvest, withdrawal recall, swap-through-vault behavior, zero-yield harvests, full withdrawal, constructor validation, only-vault gating, and slippage rejection.
- Pendle deployment, harvest, withdrawal recall, swap-through-vault behavior, only-vault gating, zero-yield harvests, and full withdrawal.
- Morpho deployment, harvest, withdrawal recall, swap-through-vault behavior, only-vault gating, zero-yield harvests, and full withdrawal.
- Hot-swapping from Pendle to Morpho and from Morpho to a mock strategy.
- Share-value preservation through strategy swaps.
- Multi-harvest behavior across adapters.

The adapter tests focus on integration behavior using mocks rather than live protocol forks. This is suitable for deterministic unit and integration tests, but it should be complemented by fork tests before production deployment.

### 5.6 Yield Distributor

Yield distributor tests cover:

- Deployment and vault registration.
- Duplicate, zero, owner-only, and removal validation.
- Removal rejection when stakers remain.
- Protocol fee collection from swaps.
- Zero-fee behavior when no distributor is configured.
- Harvest fee collection.
- Stake, claim, unstake, and full-cycle user flows.
- Multi-staker proportional fee distribution.
- Bonus reward configuration and accrual.
- Coverage-ratio weighted allocation points.
- Claim-all behavior.
- Authorized fee notifications only.
- Unregistered and zero-amount notification behavior.
- Pausing behavior.
- Emergency withdraw while paused.
- Fee buffering when no stakers exist.
- Buffered fee flush on first stake.
- Bonus carry-over during reward reconfiguration.
- Swap quote invariance when protocol fees are enabled.

The distributor suite covers both accounting correctness and operational safety paths.

## 6. Frontend Test Inventory

| Area | File | Cases | Main coverage areas |
|---|---|---:|---|
| Quote action | `app/src/app/actions/quote.test.ts` | 4 | Empty input, quote formatting, action errors, balance/allowance fallback |
| Pool action | `app/src/app/actions/pools.test.ts` | 3 | Pool-card construction, Pyth fallback, failed-read filtering, LP balance reads |
| Faucet action | `app/src/app/actions/faucet.test.ts` | 4 | Missing key, key normalization, sequential minting, partial failure, invalid key |
| Wagmi config | `app/src/lib/wagmiConfig.test.ts` | 1 | RainbowKit metadata and SSR config |
| Viem client | `app/src/lib/viemClient.test.ts` | 2 | Local/Kairos chain definitions and default test chain |
| Utilities | `app/src/lib/utils.test.ts` | 4 | Class merging, amount formatting, price/BPS formatting, address shortening |
| Pyth helpers | `app/src/lib/pyth.test.ts` | 3 | Hermes update data, empty payload failure, update fee read |
| UI primitives | `app/src/components/ui/primitives.test.tsx` | 5 | Badge, card slots, input refs, skeleton/separator, tabs |
| Button | `app/src/components/ui/button.test.tsx` | 2 | Variants, forwarded attributes, class generation |
| Token selector | `app/src/components/TokenSelector.test.tsx` | 1 | Selected-token rendering and change events |
| Swap card | `app/src/components/SwapCard.test.tsx` | 5 | Disconnected state, quote display, swap submission, approval flow, quote errors, max balance, receipt success |
| Pools grid | `app/src/components/PoolsGrid.test.tsx` | 2 | Pool count, pool stats, empty active pool count |
| Liquidity panel | `app/src/components/LiquidityPanel.test.tsx` | 5 | Disconnected state, pool statistics, deposit, approval, withdrawal, receipt refresh |
| Intents panel | `app/src/components/IntentsPanel.test.tsx` | 5 | Disconnected state, intent submission, approval requirement, lookup/cancel, success intent ID |
| Header | `app/src/components/Header.test.tsx` | 1 | Branding, network badge, wallet control |
| Faucet card | `app/src/components/FaucetCard.test.tsx` | 3 | Disconnected state, token request, submitted links, partial errors |
| Total |  | 50 |  |

## 7. Frontend Coverage Assessment

The frontend suite is well targeted at behavior rather than snapshots. It verifies:

- Server action formatting and error resilience.
- Contract read/write failure handling.
- Wallet-connected and wallet-disconnected UI states.
- Approval-first transaction flows.
- Successful transaction receipt handling.
- Partial success/error states for faucet requests.
- Component-level behavior for swap, liquidity, pools, intents, token selection, and shared UI primitives.

The tests rely on deterministic mocks and local-chain environment variables from `src/test/setup.ts`. This is appropriate for fast CI tests. However, there is no evidence that these tests currently run in CI.

## 8. Key Findings

| Severity | Finding | Evidence | Impact | Recommendation |
|---|---|---|---|---|
| Medium | Branch coverage is materially lower than line/function coverage in the Solidity suite | Supplied Foundry coverage reports 24.24% branch coverage versus 96.51% line coverage and 95.89% function coverage | Untested conditional paths may remain in high-value accounting, settlement, and strategy logic | Add targeted branch tests and fuzz/invariant tests for fee, pool, settlement, strategy, and vault edge cases |
| Medium | CI only runs Foundry checks | `.github/workflows/test.yml` has no frontend job | Frontend regressions may merge without automated detection | Add a Node job for `npm ci`, `npm test`, and optionally `npm run build` under `app` |
| Medium | README test count is stale | README says 111 Foundry tests; source contains 178 Solidity tests | Documentation can mislead reviewers and release stakeholders | Update README test-suite table to match current source |
| Medium | Test and coverage evidence is screenshot-based rather than committed machine-readable artifacts | Results were supplied as terminal screenshots; no coverage directory or test report artifact is present in the repository | Future reviewers cannot diff or independently process historical coverage results | Publish Foundry and Vitest coverage summaries as CI artifacts |
| Low | Local review environment is missing test tooling | `forge` is unavailable; `npm.cmd test` cannot find `vitest`; `node_modules` is absent | The reviewer environment cannot independently reproduce the supplied results without setup | Install Foundry and run `npm ci` before future local verification |
| Low | Frontend README is stale Create React App text | `app/README.md` describes CRA while package uses Next.js 15 and Vitest | Developer onboarding friction | Replace with project-specific Next.js/Vitest instructions |
| Low | Solidity test comments show mojibake box-drawing characters | Several test files contain corrupted decorative comments | Cosmetic readability issue | Re-save or simplify decorative comments as ASCII |

## 9. Coverage Strengths

- Strong contract-side scenario coverage by intent: many tests explicitly target invalid inputs, access control, pausing, zero values, upper bounds, stale or failing oracle sources, insufficient liquidity, and duplicate operations.
- Good economic-path coverage: swaps, quotes, fee accrual, protocol fee splits, harvest fees, staking distribution, bonus rewards, and coverage-weighted allocation are all tested.
- Good modular integration coverage: tests exercise pools, vaults, strategies, distributors, settlement, and oracles together through realistic flows.
- Frontend tests cover user-facing transaction decision points, including approval requirements, disconnected states, successful writes, receipt-driven refreshes, and action-level fallback behavior.

## 10. Coverage Gaps and Residual Risks

- The supplied results show 228/228 tests passing, but this report could not independently rerun them in the local environment because Foundry and frontend dependencies are missing.
- Solidity branch coverage is low at 24.24%, despite strong line, statement, and function coverage.
- Frontend branch coverage is acceptable at 80.76%, but targeted gaps remain in `SwapCard.tsx`, `PoolsGrid.tsx`, `app/actions/pools.ts`, `app/actions/quote.ts`, and `viemClient.ts`.
- Smart contract tests use mocks for external DeFi integrations. This is deterministic, but it does not validate live Aave, Pendle, Morpho, Orakl, Pyth, or Kaia protocol behavior.
- No invariant, fuzz, or property-based test suite was identified for pool solvency, quote monotonicity, fee conservation, netting conservation, or vault share accounting.
- CI does not run frontend tests.
- CI does not publish gas snapshots, coverage reports, or frontend test artifacts.
- Deployment scripts and broadcast output are present, but no automated deployment-script test was identified.
- Frontend tests appear unit/component oriented; no browser-level end-to-end test was identified for the full swap/liquidity/intent workflows against a local chain.


## 11. Overall Assessment

The repository has a substantial and thoughtfully scoped automated test suite. Based on the supplied test outputs, all 178 Foundry tests and all 50 frontend Vitest tests pass, for a total of 228 passing tests and 0 failures. Contract line, statement, and function coverage are high at approximately 96%, while frontend coverage is also strong with 93.14% line coverage and 80.76% branch coverage.

The main quality risk is now concentrated in Solidity branch coverage and CI completeness rather than basic test breadth. Adding frontend CI, publishing machine-readable coverage artifacts, and expanding Solidity branch/fuzz/invariant coverage would make the project much more auditable for production readiness.
