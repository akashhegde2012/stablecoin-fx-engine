import { type Address } from "viem";

// ─── Addresses (from .env) ──────────────────────────────────────────────────

export const FXENGINE_ADDRESS = process.env
  .NEXT_PUBLIC_FXENGINE_ADDRESS as Address;

export const TOKEN_ADDRESSES = {
  MYR:  process.env.NEXT_PUBLIC_TOKEN_MYR  as Address,
  SGD:  process.env.NEXT_PUBLIC_TOKEN_SGD  as Address,
  IDRX: process.env.NEXT_PUBLIC_TOKEN_IDRX as Address,
  USDT: process.env.NEXT_PUBLIC_TOKEN_USDT as Address,
} as const;

export const POOL_ADDRESSES = {
  MYR:  process.env.NEXT_PUBLIC_POOL_MYR  as Address,
  SGD:  process.env.NEXT_PUBLIC_POOL_SGD  as Address,
  IDRX: process.env.NEXT_PUBLIC_POOL_IDRX as Address,
  USDT: process.env.NEXT_PUBLIC_POOL_USDT as Address,
} as const;

// ─── Oracle Aggregators (hardcoded — deployment-time constants) ─────────────
// Orakl is the primary push oracle; Pyth is the fallback pull oracle.
// These addresses come from broadcast/Deploy.s.sol/1001/run-latest.json.

export const ORACLE_ADDRESSES = {
  MYR:  "0x9dd6cFaDA795eeb5b5af651C86f2201a7BAe1730" as Address,
  SGD:  "0x7c549bE7f6d57561EcF2b08544841Be653E0A9d8" as Address,
  IDRX: "0x33530BD6aA8BCB70319339CDe9fEF66CB66fCF9c" as Address,
  USDT: "0xBd559E47880470e0A6502dFA6c252a815C2A6591" as Address,
} as const;

export const ORACLE_AGGREGATOR_ABI = [
  {
    name: "getOraklPrice",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "price",    type: "int256" },
      { name: "decimals", type: "uint8"  },
    ],
  },
  {
    name: "getPythPrice",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "price",    type: "int256" },
      { name: "decimals", type: "uint8"  },
    ],
  },
] as const;

// ─── Pyth Network ───────────────────────────────────────────────────────────

export const PYTH_CONTRACT_ADDRESS =
  "0x2880aB155794e7179c9eE2e38200202908C17B43" as Address;

export const PYTH_PRICE_FEED_IDS = {
  MYR:  "0x6049eac22964b1ac2119e54c98f3caa165817d84273a121ee122fafb664a8094",
  SGD:  "0x396a969a9c1480fa15ed50bc59149e2c0075a72fe8f458ed941ddec48bdb4918",
  IDRX: "0x6693afcd49878bbd622e46bd805e7177932cf6ab0b1c91b135d71151b9207433",
  USDT: "0x2b89b9dc8fdf9f34709a5b106b472f0f39bb6ca9ce04b0fd7f2e971688e2e53b",
} as const;

export const HERMES_ENDPOINT = "https://hermes.pyth.network";

export const TOKENS = [
  { symbol: "MYR",  name: "Malaysian Ringgit",   address: TOKEN_ADDRESSES.MYR,  pool: POOL_ADDRESSES.MYR,  decimals: 18, flag: "MY" },
  { symbol: "SGD",  name: "Singapore Dollar",    address: TOKEN_ADDRESSES.SGD,  pool: POOL_ADDRESSES.SGD,  decimals: 18, flag: "SG" },
  { symbol: "IDRX", name: "Indonesian Rupiah",   address: TOKEN_ADDRESSES.IDRX, pool: POOL_ADDRESSES.IDRX, decimals: 18, flag: "ID" },
  { symbol: "USDT", name: "Tether USD",          address: TOKEN_ADDRESSES.USDT, pool: POOL_ADDRESSES.USDT, decimals: 18, flag: "US" },
] as const;

export type TokenSymbol = (typeof TOKENS)[number]["symbol"];

// ─── ABIs ───────────────────────────────────────────────────────────────────

export const FXENGINE_ABI = [
  {
    name: "getQuote",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "tokenIn",  type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "amountIn", type: "uint256" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    name: "getPoolInfo",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "token", type: "address" }],
    outputs: [
      { name: "pool",          type: "address" },
      { name: "lpToken",       type: "address" },
      { name: "balance",       type: "uint256" },
      { name: "baseFee",       type: "uint256" },
      { name: "maxFee",        type: "uint256" },
      { name: "price",         type: "int256"  },
      { name: "priceDecimals", type: "uint8"   },
    ],
  },
  {
    name: "getRegisteredTokens",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address[]" }],
  },
  {
    name: "swap",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn",      type: "address" },
      { name: "tokenOut",     type: "address" },
      { name: "amountIn",     type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "to",           type: "address" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    name: "swapWithPythUpdate",
    type: "function",
    stateMutability: "payable",
    inputs: [
      { name: "updateData",  type: "bytes[]" },
      { name: "tokenIn",     type: "address" },
      { name: "tokenOut",    type: "address" },
      { name: "amountIn",    type: "uint256" },
      { name: "minAmountOut",type: "uint256" },
      { name: "to",          type: "address" },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    name: "Swapped",
    type: "event",
    inputs: [
      { name: "sender",    type: "address", indexed: true  },
      { name: "tokenIn",   type: "address", indexed: true  },
      { name: "tokenOut",  type: "address", indexed: true  },
      { name: "amountIn",  type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
      { name: "to",        type: "address", indexed: false },
    ],
  },
] as const;

// Pyth contract ABI (minimal, for getUpdateFee)
export const PYTH_ABI = [
  {
    name: "getUpdateFee",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "updateData", type: "bytes[]" }],
    outputs: [{ name: "feeAmount", type: "uint256" }],
  },
] as const;

export const ERC20_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "value",   type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner",   type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "symbol",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
  {
    name: "decimals",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
] as const;

export const FXPOOL_ABI = [
  {
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [{ name: "lpMinted", type: "uint256" }],
  },
  {
    name: "withdraw",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "lpAmount", type: "uint256" }],
    outputs: [{ name: "amount", type: "uint256" }],
  },
  {
    name: "getPoolBalance",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "feeRate",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getEffectiveFeeRate",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "grossOutAmount", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "lpToStablecoinRate",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "lpToken",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "platformFeeBps",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "utilizationFactor",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "maxDynamicFeeRate",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "platformTreasury",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "Deposited",
    type: "event",
    inputs: [
      { name: "provider", type: "address", indexed: true  },
      { name: "amount",   type: "uint256", indexed: false },
      { name: "lpMinted", type: "uint256", indexed: false },
    ],
  },
  {
    name: "Withdrawn",
    type: "event",
    inputs: [
      { name: "provider", type: "address", indexed: true  },
      { name: "lpBurned", type: "uint256", indexed: false },
      { name: "amount",   type: "uint256", indexed: false },
    ],
  },
] as const;

// ─── Settlement Engine ───────────────────────────────────────────────────────

export const SETTLEMENT_ENGINE_ADDRESS = (
  process.env.NEXT_PUBLIC_SETTLEMENT_ENGINE_ADDRESS ?? undefined
) as Address | undefined;

export const SETTLEMENT_ENGINE_ABI = [
  // Inherits FXEngine swap/getQuote
  {
    name: "getMultiHopQuote",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "path",     type: "address[]" },
      { name: "amountIn", type: "uint256"   },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    name: "swapMultiHop",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "path",         type: "address[]" },
      { name: "amountIn",     type: "uint256"   },
      { name: "minAmountOut", type: "uint256"   },
      { name: "to",           type: "address"   },
    ],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  {
    name: "submitIntent",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenIn",      type: "address" },
      { name: "tokenOut",     type: "address" },
      { name: "amountIn",     type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "deadline",     type: "uint256" },
    ],
    outputs: [{ name: "intentId", type: "uint256" }],
  },
  {
    name: "cancelIntent",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "intentId", type: "uint256" }],
    outputs: [],
  },
  {
    name: "getIntent",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "intentId", type: "uint256" }],
    outputs: [
      { name: "trader",       type: "address" },
      { name: "tokenIn",      type: "address" },
      { name: "tokenOut",     type: "address" },
      { name: "amountIn",     type: "uint256" },
      { name: "minAmountOut", type: "uint256" },
      { name: "deadline",     type: "uint256" },
      { name: "settled",      type: "bool"    },
      { name: "cancelled",    type: "bool"    },
    ],
  },
  {
    name: "nextIntentId",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "IntentSubmitted",
    type: "event",
    inputs: [
      { name: "intentId",     type: "uint256", indexed: true  },
      { name: "trader",       type: "address", indexed: true  },
      { name: "tokenIn",      type: "address", indexed: false },
      { name: "tokenOut",     type: "address", indexed: false },
      { name: "amountIn",     type: "uint256", indexed: false },
      { name: "minAmountOut", type: "uint256", indexed: false },
      { name: "deadline",     type: "uint256", indexed: false },
    ],
  },
  {
    name: "IntentCancelled",
    type: "event",
    inputs: [{ name: "intentId", type: "uint256", indexed: true }],
  },
  {
    name: "IntentSettled",
    type: "event",
    inputs: [
      { name: "intentId",  type: "uint256", indexed: true  },
      { name: "amountOut", type: "uint256", indexed: false },
    ],
  },
  {
    name: "MultiHopSwapped",
    type: "event",
    inputs: [
      { name: "sender",    type: "address", indexed: true  },
      { name: "tokenIn",   type: "address", indexed: false },
      { name: "tokenOut",  type: "address", indexed: false },
      { name: "amountIn",  type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
      { name: "hops",      type: "uint256", indexed: false },
      { name: "to",        type: "address", indexed: false },
    ],
  },
] as const;
