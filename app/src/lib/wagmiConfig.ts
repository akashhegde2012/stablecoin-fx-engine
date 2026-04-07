"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { anvilChain, kairosChain } from "./viemClient";

export const wagmiConfig = getDefaultConfig({
  appName: "KAIA FX",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "kaia-fx-dev",
  chains: [kairosChain, anvilChain],
  ssr: true,
});
