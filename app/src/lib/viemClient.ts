import { createPublicClient, http, defineChain } from "viem";

/** Anvil local chain */
export const anvilChain = defineChain({
  id: Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 31337),
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_RPC_URL ?? "http://127.0.0.1:8545"] },
  },
});

/** Server-side public client — used in server actions only. */
export const publicClient = createPublicClient({
  chain: anvilChain,
  transport: http(process.env.NEXT_PUBLIC_RPC_URL ?? "http://127.0.0.1:8545"),
});
