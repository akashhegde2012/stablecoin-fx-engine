import { createPublicClient, http, defineChain } from "viem";

export const anvilChain = defineChain({
  id: 31337,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
  },
});

export const kairosChain = defineChain({
  id: 1001,
  name: "Kaia Kairos",
  nativeCurrency: { name: "KAIA", symbol: "KAIA", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://public-en-kairos.node.kaia.io"] },
  },
  blockExplorers: {
    default: { name: "Kaiascan", url: "https://kairos.kaiascan.io" },
  },
  testnet: true,
});

const chainId = Number(process.env.NEXT_PUBLIC_CHAIN_ID ?? 31337);

export const activeChain =
  chainId === 1001 ? kairosChain : anvilChain;

export const rpcUrl =
  process.env.NEXT_PUBLIC_RPC_URL ??
  (chainId === 1001
    ? "https://public-en-kairos.node.kaia.io"
    : "http://127.0.0.1:8545");

/** Server-side public client — used in server actions only. */
export const publicClient = createPublicClient({
  chain: activeChain,
  transport: http(rpcUrl),
});
