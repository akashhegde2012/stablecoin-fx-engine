"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Zap } from "lucide-react";

export function Header() {
  return (
    <header className="sticky top-0 z-50 border-b border-kaia-border bg-kaia-bg/80 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4">
        {/* Logo */}
        <div className="flex items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-kaia-primary/15 border border-kaia-primary/30">
            <Zap className="h-5 w-5 text-kaia-primary" strokeWidth={2.5} />
          </div>
          <div>
            <span className="text-lg font-bold text-kaia-text tracking-tight">KAIA</span>
            <span className="ml-1 text-lg font-bold text-kaia-primary tracking-tight">FX</span>
          </div>
          <span className="ml-1 rounded-full border border-kaia-primary/30 bg-kaia-primary/10 px-2 py-0.5 text-[10px] font-semibold text-kaia-primary uppercase tracking-wider">
            Testnet
          </span>
        </div>

        {/* Wallet */}
        <ConnectButton
          accountStatus="avatar"
          chainStatus="icon"
          showBalance={false}
        />
      </div>
    </header>
  );
}
