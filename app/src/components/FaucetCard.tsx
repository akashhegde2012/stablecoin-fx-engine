"use client";

import React, { useState, useTransition } from "react";
import { Droplets, CheckCircle2, AlertCircle, Loader2, ExternalLink } from "lucide-react";
import { useAccount } from "wagmi";
import { Button }        from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { requestTestTokens } from "@/app/actions/faucet";
import { useRouter } from "next/navigation";

const AMOUNTS: Record<string, string> = {
  MYR:  "44,092",
  SGD:  "13,479",
  IDRX: "162,074,550",
  USDT: "10,000",
};

const FLAG: Record<string, string> = { MYR: "🇲🇾", SGD: "🇸🇬", IDRX: "🇮🇩", USDT: "🇺🇸" };

export function FaucetCard() {
  const { address, isConnected } = useAccount();
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [hashes, setHashes] = useState<Record<string, string> | null>(null);
  const [error,  setError]  = useState<string>("");

  const handleRequest = () => {
    if (!address) return;
    setHashes(null);
    setError("");
    startTransition(async () => {
      const result = await requestTestTokens(address);
      if (result.success && result.hashes) {
        setHashes(result.hashes);
        router.refresh();
      } else {
        setError(result.error ?? "Unknown error");
        if (result.hashes) setHashes(result.hashes); // partial success
      }
    });
  };

  return (
    <Card className="w-full max-w-md mx-auto">
      <CardContent className="pt-6 space-y-5">
        {/* Header */}
        <div className="flex items-center gap-2.5">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-kaia-primary/15 border border-kaia-primary/30">
            <Droplets className="h-5 w-5 text-kaia-primary" />
          </div>
          <div>
            <h2 className="text-xl font-bold text-kaia-text">Testnet Faucet</h2>
            <p className="text-xs text-kaia-muted">Receive test tokens on Kaia Kairos</p>
          </div>
        </div>

        {/* Token amounts */}
        <div className="rounded-xl border border-kaia-border bg-kaia-surface/50 p-4 space-y-2">
          <p className="text-xs font-medium text-kaia-muted mb-3">You will receive (≈ $10 000 USD each)</p>
          {Object.entries(AMOUNTS).map(([sym, amt]) => (
            <div key={sym} className="flex items-center justify-between text-sm">
              <span className="flex items-center gap-2 text-kaia-muted">
                <span>{FLAG[sym]}</span>
                <span>{sym}</span>
              </span>
              <span className="font-semibold text-kaia-text">{amt}</span>
            </div>
          ))}
        </div>

        {/* Success */}
        {hashes && Object.keys(hashes).length > 0 && (
          <div className="rounded-xl border border-kaia-primary/30 bg-kaia-primary/10 px-4 py-3 space-y-2">
            <div className="flex items-center gap-2 text-xs text-kaia-primary font-medium">
              <CheckCircle2 className="h-4 w-4" />
              Tokens minted! Transactions submitted:
            </div>
            {Object.entries(hashes).map(([sym, hash]) => (
              <div key={sym} className="flex items-center justify-between text-xs">
                <span className="text-kaia-muted">{FLAG[sym]} {sym}</span>
                <a
                  href={`https://kairos.kaiascan.io/tx/${hash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-1 font-mono text-kaia-primary hover:underline"
                >
                  {hash.slice(0, 10)}…{hash.slice(-6)}
                  <ExternalLink className="h-3 w-3" />
                </a>
              </div>
            ))}
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="flex items-start gap-2 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-xs text-red-400">
            <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* CTA */}
        {!isConnected ? (
          <Button variant="secondary" className="w-full" disabled>
            Connect Wallet to Request Tokens
          </Button>
        ) : (
          <Button
            className="w-full"
            onClick={handleRequest}
            disabled={isPending}
          >
            {isPending ? (
              <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Minting tokens…</>
            ) : (
              <><Droplets className="mr-2 h-4 w-4" /> Request Test Tokens</>
            )}
          </Button>
        )}

        <p className="text-center text-xs text-kaia-muted">
          Kairos testnet only · No real value · One request per session
        </p>
      </CardContent>
    </Card>
  );
}
