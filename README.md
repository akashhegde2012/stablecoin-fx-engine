# SSL FX Engine

A modular on-chain FX settlement engine for stablecoin swaps with integrated yield generation, built on the [Kaia](https://kaia.io) blockchain using [Orakl Network](https://orakl.network) price feeds.

## Architecture

```
                          ┌──────────────────────────────────┐
                          │        YieldDistributor          │
                          │  fee collection · LP staking     │
                          │  bonus rewards · coverage APY    │
                          └──────┬──────────────┬────────────┘
                     protocol   │              │  harvest
                     fees       │              │  fees
                                │              │
┌───────────────────────────────┴──┐  ┌────────┴─────────────────────┐
│    FXEngine / SettlementEngine   │  │         YieldVault (×N)      │
│  swap · multi-hop · netting      │  │  ERC-4626 · IFXPool compat  │
│  protocol fee extraction         │  │  coverage ratio management   │
└──────────┬───────────────────────┘  └──────────┬───────────────────┘
           │  release / deposit                  │  deploy / recall
           │                                     │
    ┌──────┴──────┐                       ┌──────┴──────┐
    │   FXPool    │                       │ IYieldStrategy │
    │ single-sided│                       │  (pluggable)   │
    │  liquidity  │                       └──┬───┬───┬─────┘
    └─────────────┘                          │   │   │
                                   Aave ─────┘   │   └───── Morpho
                                          Pendle ─┘
```

## Contracts

### Core

| Contract | Path | Description |
|----------|------|-------------|
| `FXEngine` | `src/FXEngine.sol` | Stateless swap router. Fetches USD prices from Orakl feeds, computes cross-rate, deducts pool fee, extracts protocol fee to distributor. |
| `FXPool` | `src/pools/FXPool.sol` | Single-sided liquidity pool for one stablecoin. Dead-share inflation protection, oracle staleness checks, pausable. |
| `LPToken` | `src/pools/LPToken.sol` | ERC-20 LP share token owned by its FXPool. |

### Yield Layer (Phase 1 + 3)

| Contract | Path | Description |
|----------|------|-------------|
| `YieldVault` | `src/vaults/YieldVault.sol` | ERC-4626 vault replacing FXPool for yield-enabled pools. Manages coverage ratio, deploys idle capital to strategies, auto-recalls on withdrawals. |
| `BaseStrategy` | `src/strategies/BaseStrategy.sol` | Abstract adapter skeleton with `onlyVault` gating and slippage constants. |
| `AaveStrategy` | `src/strategies/AaveStrategy.sol` | Deploys stablecoins into Aave V3 lending. |
| `PendleStrategy` | `src/strategies/PendleStrategy.sol` | Deploys into Pendle SY tokens with slippage-protected deposits/withdrawals. |
| `MorphoStrategy` | `src/strategies/MorphoStrategy.sol` | Deploys into MetaMorpho (Morpho Blue) curated vaults. |

### Settlement Layer (Phase 2)

| Contract | Path | Description |
|----------|------|-------------|
| `SettlementEngine` | `src/settlement/SettlementEngine.sol` | Extends FXEngine with multi-hop routing and intent-based netting. Protocol fees on multi-hop swaps. |
| `NettingLib` | `src/settlement/NettingLib.sol` | Pure library for computing net bilateral token flows after netting opposing swap intents. |

### Distribution Layer (Phase 4)

| Contract | Path | Description |
|----------|------|-------------|
| `YieldDistributor` | `src/distribution/YieldDistributor.sol` | MasterChef-style staking contract. Collects protocol swap fees + harvest fees, distributes to LP stakers weighted by coverage ratio. Supports bonus reward token drip. |

### Tokens

| Contract | Path | Description |
|----------|------|-------------|
| `StablecoinToken` | `src/tokens/StablecoinToken.sol` | Abstract ERC-20 base with owner-controlled minting. |
| `USDTToken` | `src/tokens/USDTToken.sol` | Tether USD (18 decimals). |
| `SGDToken` | `src/tokens/SGDToken.sol` | Singapore Dollar stablecoin. |
| `MYRToken` | `src/tokens/MYRToken.sol` | Malaysian Ringgit stablecoin. |
| `IDRXToken` | `src/tokens/IDRXToken.sol` | Indonesian Rupiah stablecoin. |

### Interfaces

| Interface | Purpose |
|-----------|---------|
| `IFXPool` | Standard pool interface (deposit, withdraw, release, getPrice) |
| `IYieldStrategy` | Strategy adapter interface (deposit, withdraw, harvest, totalValue) |
| `IYieldDistributor` | Fee notification interface for engine/vault integration |
| `IAavePool` | Minimal Aave V3 Pool interface |
| `IPendleSYToken` | Minimal Pendle SY token interface |
| `IMorphoVault` | Minimal MetaMorpho vault interface (ERC-4626 subset) |
| `IOraklFeed` | Orakl Network v0.2 data feed interface |

## Security Features

- **Inflation attack protection** — Dead shares (FXPool) and dead-share lock on first ERC-4626 deposit (YieldVault)
- **Oracle staleness checks** — Configurable `maxStaleness` rejects stale price data
- **Reentrancy guards** — All public entry points on all contracts (including ERC-4626 functions)
- **Pausable** — Owner can halt all operations across FXEngine, FXPool, YieldVault, SettlementEngine, and YieldDistributor
- **Two-step engine setter** — `proposeEngine()` + `acceptEngine()` prevents instant fund-drain
- **Strategy slippage protection** — All adapters enforce 0.5% max slippage on DeFi protocol interactions
- **Intent deadline cap** — Max 7-day deadline on swap intents
- **Liquidity recall verification** — `_ensureLiquidity` reverts if strategy recall doesn't cover the deficit
- **Emergency withdraw** — YieldDistributor allows share recovery even when paused
- **Undistributed fee buffering** — Fees received with zero stakers are buffered and flushed to the first staker

## Build

```bash
# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv

# Format
forge fmt
```

## Test Suite

111 tests across 5 suites:

| Suite | Tests | Coverage |
|-------|-------|----------|
| `FXEngine.t.sol` | 26 | Core swaps, LP operations, access control, edge cases |
| `YieldVault.t.sol` | 23 | ERC-4626, IFXPool compat, strategy management, coverage ratio |
| `SettlementEngine.t.sol` | 22 | Multi-hop routing, intent submission, netting, settlement |
| `StrategyAdapters.t.sol` | 18 | Pendle, Morpho, hot-swapping, multi-harvest |
| `YieldDistributor.t.sol` | 22 | Fee collection, staking, bonus rewards, coverage weighting |

## Deploy (Kaia Kairos Testnet)

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://public-en-kairos.node.kaia.io \
  --broadcast \
  --private-key <DEPLOYER_KEY>
```

### Orakl Price Feeds (Kairos)

| Pair | Proxy Address |
|------|---------------|
| MYR/USD | `0x52B73aD55d8BAAFA0f7769934bAFfb5A0Ebb02B3` |
| SGD/USD | `0x3c6D320f3b3ff80f6c8B78c1146EDb05f888aaB3` |
| IDR/USD | `0x0b5a141Fcc3d124e078FFa73c1Fc3d408fCfE306` |
| USDT/USD | `0x2D9A3d17400332c44ff0E2dC1b728529a33F5591` |

## Mint Test Tokens

```bash
forge script script/MintToWallet.s.sol \
  --rpc-url https://public-en-kairos.node.kaia.io \
  --broadcast \
  --private-key <DEPLOYER_KEY> \
  --sig "run(address)" <RECIPIENT>
```

## License

MIT
