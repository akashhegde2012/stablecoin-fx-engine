"use server";

import { formatUnits } from "viem";
import { publicClient } from "@/lib/viemClient";
import { FXENGINE_ADDRESS, FXENGINE_ABI, ERC20_ABI, TOKENS } from "@/lib/contracts";
import type { Address } from "viem";

export interface PoolInfo {
  symbol:       string;
  name:         string;
  tokenAddress: string;
  poolAddress:  string;
  lpToken:      string;
  balance:      string;   // formatted, e.g. "100,000.00"
  balanceRaw:   string;
  feeRate:      string;   // e.g. "0.30%"
  feeRateBps:   string;
  price:        string;   // e.g. "$0.2268"
  flag:         string;
}

export async function getAllPoolsInfo(): Promise<PoolInfo[]> {
  const results = await Promise.all(
    TOKENS.map(async (token) => {
      try {
        const info = await publicClient.readContract({
          address: FXENGINE_ADDRESS,
          abi:     FXENGINE_ABI,
          functionName: "getPoolInfo",
          args:    [token.address],
        });

        const [pool, lpToken, balance, fee, price, priceDecimals] = info;

        const balanceNum = parseFloat(formatUnits(balance, 18));
        const feeNum     = Number(fee);
        const priceNum   = parseFloat(formatUnits(price as bigint, priceDecimals));

        return {
          symbol:       token.symbol,
          name:         token.name,
          tokenAddress: token.address,
          poolAddress:  pool,
          lpToken,
          balance: balanceNum.toLocaleString("en-US", {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
          }),
          balanceRaw:  balance.toString(),
          feeRate:     `${(feeNum / 100).toFixed(2)}%`,
          feeRateBps:  fee.toString(),
          price: priceNum.toLocaleString("en-US", {
            style:    "currency",
            currency: "USD",
            minimumFractionDigits: 4,
            maximumFractionDigits: 6,
          }),
          flag: token.flag,
        } satisfies PoolInfo;
      } catch {
        return null;
      }
    }),
  );

  return results.filter(Boolean) as PoolInfo[];
}

export interface UserLPBalance {
  symbol:    string;
  lpToken:   string;
  lpBalance: string;
  lpBalanceRaw: string;
  /** Estimated underlying stablecoin value */
  underlying: string;
}

export async function getUserLPBalances(userAddress: Address): Promise<UserLPBalance[]> {
  const results = await Promise.all(
    TOKENS.map(async (token) => {
      try {
        const info = await publicClient.readContract({
          address: FXENGINE_ADDRESS,
          abi:     FXENGINE_ABI,
          functionName: "getPoolInfo",
          args:    [token.address],
        });
        const [, lpTokenAddr, poolBalance] = info;

        const [lpBal, lpSupply] = await Promise.all([
          publicClient.readContract({
            address: lpTokenAddr as Address,
            abi:     ERC20_ABI,
            functionName: "balanceOf",
            args:    [userAddress],
          }),
          publicClient.readContract({
            address: lpTokenAddr as Address,
            abi:     [{ name: "totalSupply", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] }] as const,
            functionName: "totalSupply",
          }),
        ]);

        const lpBalNum  = parseFloat(formatUnits(lpBal, 18));
        const underlying =
          lpSupply > 0n
            ? (lpBal * poolBalance) / lpSupply
            : 0n;

        return {
          symbol:    token.symbol,
          lpToken:   lpTokenAddr as string,
          lpBalance: lpBalNum.toLocaleString("en-US", {
            minimumFractionDigits: 4,
            maximumFractionDigits: 6,
          }),
          lpBalanceRaw: lpBal.toString(),
          underlying: parseFloat(formatUnits(underlying, 18)).toLocaleString("en-US", {
            minimumFractionDigits: 2,
            maximumFractionDigits: 4,
          }),
        } satisfies UserLPBalance;
      } catch {
        return null;
      }
    }),
  );

  return results.filter(Boolean) as UserLPBalance[];
}
