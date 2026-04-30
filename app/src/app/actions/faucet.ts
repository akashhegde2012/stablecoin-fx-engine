"use server";

import { createWalletClient, http, parseUnits } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { activeChain, rpcUrl } from "@/lib/viemClient";
import { TOKEN_ADDRESSES } from "@/lib/contracts";
import type { Address } from "viem";

const MINT_ABI = [
  {
    name: "mint",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to",     type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
  },
] as const;

const AMOUNTS = {
  MYR:  parseUnits("44092",       18),  // ≈ $10 000
  SGD:  parseUnits("13479",       18),  // ≈ $10 000
  IDRX: parseUnits("162074550",   18),  // ≈ $10 000
  USDT: parseUnits("10000",       18),  // = $10 000
} as const;

export interface FaucetResult {
  success: boolean;
  hashes?: Record<string, string>;
  error?: string;
}

export async function requestTestTokens(recipient: string): Promise<FaucetResult> {
  const rawKey = process.env.FAUCET_PRIVATE_KEY;
  if (!rawKey) {
    return { success: false, error: "Faucet not configured on this server." };
  }

  // Normalise key — accept with or without 0x prefix
  const key = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as `0x${string}`;

  let account;
  try {
    account = privateKeyToAccount(key);
  } catch {
    return { success: false, error: "Invalid faucet key configuration." };
  }

  const walletClient = createWalletClient({
    account,
    chain:     activeChain,
    transport: http(rpcUrl),
  });

  const hashes: Record<string, string> = {};

  // Mint sequentially to avoid nonce conflicts
  for (const symbol of ["MYR", "SGD", "IDRX", "USDT"] as const) {
    try {
      const hash = await walletClient.writeContract({
        address:      TOKEN_ADDRESSES[symbol] as Address,
        abi:          MINT_ABI,
        functionName: "mint",
        args:         [recipient as Address, AMOUNTS[symbol]],
      });
      hashes[symbol] = hash;
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      return {
        success: false,
        hashes,
        error: `Failed to mint ${symbol}: ${msg.slice(0, 120)}`,
      };
    }
  }

  return { success: true, hashes };
}
