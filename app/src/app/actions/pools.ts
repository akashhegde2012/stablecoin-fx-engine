"use server";

import { formatUnits } from "viem";
import { publicClient } from "@/lib/viemClient";
import {
  FXENGINE_ADDRESS,
  FXENGINE_ABI,
  FXPOOL_ABI,
  ERC20_ABI,
  ORACLE_ADDRESSES,
  ORACLE_AGGREGATOR_ABI,
  TOKENS,
} from "@/lib/contracts";
import type { Address } from "viem";

export interface PoolInfo {
  symbol:            string;
  name:              string;
  tokenAddress:      string;
  poolAddress:       string;
  lpToken:           string;
  balance:           string;
  balanceRaw:        string;
  feeRate:           string;
  feeRateBps:        string;
  maxFeeBps:         string;
  platformFeeBps:    string;
  platformFeeLabel:  string;
  lpFeePct:          string;
  utilizationFactor: string;
  price:             string;   // "$0.2268" | "—"
  priceSource:       string;   // "Orakl" | "Pyth" | "—"
  flag:              string;
}

/** Read a single pool stat; return a fallback value instead of throwing. */
async function safeRead<T>(
  address: Address,
  abi: unknown,
  functionName: string,
  fallback: T,
): Promise<T> {
  try {
    const result = await publicClient.readContract({
      address,
      abi:    abi as Parameters<typeof publicClient.readContract>[0]["abi"],
      functionName,
    } as Parameters<typeof publicClient.readContract>[0]);
    return result as T;
  } catch {
    return fallback;
  }
}

/**
 * Fetch the USD price for a pool's token.
 * Strategy: Orakl first (push oracle, always on-chain), then Pyth fallback.
 * This bypasses the OracleAggregator's cross-validation which can revert on
 * testnet when Orakl mock prices deviate from live Pyth prices.
 */
async function fetchPrice(
  symbol: keyof typeof ORACLE_ADDRESSES,
): Promise<{ price: string; source: string }> {
  const oracleAddr = ORACLE_ADDRESSES[symbol];

  // 1. Try Orakl (primary — push oracle, no staleness risk on testnet)
  try {
    const [oraklPrice, oraklDec] = await publicClient.readContract({
      address:      oracleAddr,
      abi:          ORACLE_AGGREGATOR_ABI,
      functionName: "getOraklPrice",
    });
    if (oraklPrice > 0n) {
      return {
        price: formatUsdPrice(oraklPrice, oraklDec),
        source: "Orakl",
      };
    }
  } catch {
    // Orakl unavailable — fall through to Pyth
  }

  // 2. Fallback: Pyth (pull oracle — fresh if hermes has updated recently)
  try {
    const [pythPrice, pythDec] = await publicClient.readContract({
      address:      oracleAddr,
      abi:          ORACLE_AGGREGATOR_ABI,
      functionName: "getPythPrice",
    });
    if (pythPrice > 0n) {
      return {
        price: formatUsdPrice(pythPrice, pythDec),
        source: "Pyth",
      };
    }
  } catch {
    // Both oracles unavailable
  }

  return { price: "—", source: "—" };
}

function formatUsdPrice(price: bigint, decimals: number | bigint): string {
  const num = parseFloat(formatUnits(price, Number(decimals)));
  return num.toLocaleString("en-US", {
    style: "currency", currency: "USD",
    minimumFractionDigits: 4, maximumFractionDigits: 6,
  });
}

export async function getAllPoolsInfo(): Promise<PoolInfo[]> {
  const results = await Promise.all(
    TOKENS.map(async (token) => {
      const poolAddr = token.pool as Address;

      // Read each pool stat independently — a single failed call won't kill the card
      const [balance, baseFee, maxFee, lpToken, platformFee, utilFactor] =
        await Promise.all([
          safeRead<bigint>(poolAddr, FXPOOL_ABI, "getPoolBalance",    0n),
          safeRead<bigint>(poolAddr, FXPOOL_ABI, "feeRate",           0n),
          safeRead<bigint>(poolAddr, FXPOOL_ABI, "maxDynamicFeeRate", 0n),
          safeRead<string>(poolAddr, FXPOOL_ABI, "lpToken",           poolAddr),
          safeRead<bigint>(poolAddr, FXPOOL_ABI, "platformFeeBps",    0n),
          safeRead<bigint>(poolAddr, FXPOOL_ABI, "utilizationFactor", 0n),
        ]);

      // Price: Orakl primary, Pyth fallback — no cross-validation
      const { price, source: priceSource } =
        await fetchPrice(token.symbol as keyof typeof ORACLE_ADDRESSES);

      const balanceNum  = parseFloat(formatUnits(balance, 18));
      const baseFeeNum  = Number(baseFee);
      const maxFeeNum   = Number(maxFee);
      const platformBps = Number(platformFee);
      const lpBps       = 10_000 - platformBps;

      return {
        symbol:            token.symbol,
        name:              token.name,
        tokenAddress:      token.address,
        poolAddress:       poolAddr,
        lpToken:           lpToken as string,
        balance: balanceNum.toLocaleString("en-US", {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        }),
        balanceRaw:        balance.toString(),
        feeRate:           `${(baseFeeNum / 100).toFixed(2)}% – ${(maxFeeNum / 100).toFixed(2)}%`,
        feeRateBps:        baseFee.toString(),
        maxFeeBps:         maxFee.toString(),
        platformFeeBps:    platformFee.toString(),
        platformFeeLabel:  `${(platformBps / 100).toFixed(0)}%`,
        lpFeePct:          `${(lpBps / 100).toFixed(0)}%`,
        utilizationFactor: utilFactor.toString(),
        price,
        priceSource,
        flag: token.flag,
      } satisfies PoolInfo;
    }),
  );

  // Filter out any pools where balance is 0 AND lpToken is the pool address itself
  // (sentinel value from safeRead means pool is truly unreachable)
  return results.filter(
    (p) => p !== null && p.poolAddress !== p.lpToken,
  ) as PoolInfo[];
}

export interface UserLPBalance {
  symbol:       string;
  lpToken:      string;
  lpBalance:    string;
  lpBalanceRaw: string;
  underlying:   string;
}

export async function getUserLPBalances(userAddress: Address): Promise<UserLPBalance[]> {
  const results = await Promise.all(
    TOKENS.map(async (token) => {
      try {
        const lpTokenAddr = await publicClient.readContract({
          address:      token.pool as Address,
          abi:          FXPOOL_ABI,
          functionName: "lpToken",
        });

        const [lpBal, lpSupply, poolBalance] = await Promise.all([
          publicClient.readContract({
            address:      lpTokenAddr as Address,
            abi:          ERC20_ABI,
            functionName: "balanceOf",
            args:         [userAddress],
          }),
          publicClient.readContract({
            address:      lpTokenAddr as Address,
            abi:          [{ name: "totalSupply", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] }] as const,
            functionName: "totalSupply",
          }),
          publicClient.readContract({
            address:      token.pool as Address,
            abi:          FXPOOL_ABI,
            functionName: "getPoolBalance",
          }),
        ]);

        const underlying =
          lpSupply > 0n ? (lpBal * poolBalance) / lpSupply : 0n;

        return {
          symbol:    token.symbol,
          lpToken:   lpTokenAddr as string,
          lpBalance: parseFloat(formatUnits(lpBal, 18)).toLocaleString("en-US", {
            minimumFractionDigits: 4, maximumFractionDigits: 6,
          }),
          lpBalanceRaw: lpBal.toString(),
          underlying:   parseFloat(formatUnits(underlying, 18)).toLocaleString("en-US", {
            minimumFractionDigits: 2, maximumFractionDigits: 4,
          }),
        } satisfies UserLPBalance;
      } catch {
        return null;
      }
    }),
  );
  return results.filter(Boolean) as UserLPBalance[];
}
