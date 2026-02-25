"use server";

import { parseUnits } from "viem";
import { publicClient } from "@/lib/viemClient";
import { FXENGINE_ADDRESS, FXENGINE_ABI, ERC20_ABI } from "@/lib/contracts";
import type { Address } from "viem";

export interface QuoteResult {
  amountOut: string;
  amountOutRaw: string;
  rateDisplay: string;
  error?: string;
}

export async function getSwapQuote(
  tokenIn: Address,
  tokenOut: Address,
  amountInStr: string,
  tokenInSymbol: string,
  tokenOutSymbol: string,
): Promise<QuoteResult> {
  try {
    if (!amountInStr || parseFloat(amountInStr) <= 0) {
      return { amountOut: "", amountOutRaw: "0", rateDisplay: "" };
    }

    const amountIn = parseUnits(amountInStr, 18);

    const amountOut = await publicClient.readContract({
      address: FXENGINE_ADDRESS,
      abi: FXENGINE_ABI,
      functionName: "getQuote",
      args: [tokenIn, tokenOut, amountIn],
    });

    // Also compute 1-unit rate
    const oneUnit = parseUnits("1", 18);
    const rateRaw = await publicClient.readContract({
      address: FXENGINE_ADDRESS,
      abi: FXENGINE_ABI,
      functionName: "getQuote",
      args: [tokenIn, tokenOut, oneUnit],
    });

    const rateNum = parseFloat(formatUnitsSimple(rateRaw, 18));
    const outNum  = parseFloat(formatUnitsSimple(amountOut, 18));

    return {
      amountOut: outNum.toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 6,
      }),
      amountOutRaw: amountOut.toString(),
      rateDisplay: `1 ${tokenInSymbol} = ${rateNum.toLocaleString("en-US", {
        minimumFractionDigits: 4,
        maximumFractionDigits: 6,
      })} ${tokenOutSymbol}`,
    };
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    return { amountOut: "", amountOutRaw: "0", rateDisplay: "", error: msg };
  }
}

export async function getUserTokenBalance(
  tokenAddress: Address,
  userAddress: Address,
): Promise<string> {
  try {
    const balance = await publicClient.readContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [userAddress],
    });
    return balance.toString();
  } catch {
    return "0";
  }
}

export async function getAllowance(
  tokenAddress: Address,
  owner: Address,
  spender: Address,
): Promise<string> {
  try {
    const allowance = await publicClient.readContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "allowance",
      args: [owner, spender],
    });
    return allowance.toString();
  } catch {
    return "0";
  }
}

/** Minimal formatUnits without importing ethers (avoid bundle bloat server-side) */
function formatUnitsSimple(value: bigint, decimals: number): string {
  const str = value.toString().padStart(decimals + 1, "0");
  const intPart = str.slice(0, str.length - decimals) || "0";
  const fracPart = str.slice(str.length - decimals).replace(/0+$/, "");
  return fracPart ? `${intPart}.${fracPart}` : intPart;
}
