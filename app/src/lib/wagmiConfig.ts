"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { anvilChain } from "./viemClient";

export const wagmiConfig = getDefaultConfig({
  appName: "KAIA FX",
  projectId: "kaia-fx-local",   // WalletConnect project ID (fine for local dev)
  chains: [anvilChain],
  ssr: true,
});
