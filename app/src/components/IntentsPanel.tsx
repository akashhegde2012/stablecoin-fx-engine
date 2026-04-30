"use client";

import React, { useState, useCallback, useTransition } from "react";
import {
  Clock,
  PlusCircle,
  XCircle,
  Loader2,
  CheckCircle2,
  AlertCircle,
  Info,
  ArrowRight,
} from "lucide-react";
import { parseUnits, formatUnits, maxUint256 } from "viem";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";

import { Button }        from "@/components/ui/button";
import { Input }         from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Badge }         from "@/components/ui/badge";
import { TokenSelector } from "@/components/TokenSelector";
import {
  TOKENS,
  TOKEN_ADDRESSES,
  SETTLEMENT_ENGINE_ADDRESS,
  SETTLEMENT_ENGINE_ABI,
  ERC20_ABI,
} from "@/lib/contracts";
import { formatAmount }  from "@/lib/utils";
import type { TokenSymbol } from "@/lib/contracts";

const FLAG_EMOJI: Record<string, string> = {
  MY: "🇲🇾", SG: "🇸🇬", ID: "🇮🇩", US: "🇺🇸",
};

function tokenFlag(symbol: string): string {
  const t = TOKENS.find((x) => x.symbol === symbol);
  return t ? (FLAG_EMOJI[t.flag] ?? "") : "";
}

/** 7-day deadline from now (matches MAX_INTENT_DURATION) */
function defaultDeadline(): bigint {
  return BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60);
}

export function IntentsPanel() {
  const { address, isConnected } = useAccount();

  // ── Intent submission state ──────────────────────────────────────────────
  const [tokenIn,    setTokenIn]    = useState<TokenSymbol>("MYR");
  const [tokenOut,   setTokenOut]   = useState<TokenSymbol>("SGD");
  const [amountIn,   setAmountIn]   = useState("");
  const [minOut,     setMinOut]     = useState("");
  const [slippage,   setSlippage]   = useState("1.0");
  const [intentId,   setIntentId]   = useState<string | null>(null);

  const tokenInAddr  = TOKEN_ADDRESSES[tokenIn  as keyof typeof TOKEN_ADDRESSES];
  const tokenOutAddr = TOKEN_ADDRESSES[tokenOut as keyof typeof TOKEN_ADDRESSES];

  // ── Read allowance ───────────────────────────────────────────────────────
  const { data: allowance = 0n, refetch: refetchAllowance } = useReadContract({
    address:      tokenInAddr,
    abi:          ERC20_ABI,
    functionName: "allowance",
    args:         address && SETTLEMENT_ENGINE_ADDRESS
                    ? [address, SETTLEMENT_ENGINE_ADDRESS]
                    : undefined,
    query:        { enabled: !!address && !!SETTLEMENT_ENGINE_ADDRESS },
  });

  // ── Read next intent ID (to enumerate user intents) ──────────────────────
  const { data: nextId = 0n } = useReadContract({
    address:      SETTLEMENT_ENGINE_ADDRESS,
    abi:          SETTLEMENT_ENGINE_ABI,
    functionName: "nextIntentId",
    query:        { enabled: !!SETTLEMENT_ENGINE_ADDRESS },
  });

  // ── Approve ──────────────────────────────────────────────────────────────
  const { writeContract: approve, data: approveTxHash, isPending: approveLoading } =
    useWriteContract();
  const { isSuccess: approveSuccess, isLoading: approveConfirming } =
    useWaitForTransactionReceipt({ hash: approveTxHash });
  React.useEffect(() => { if (approveSuccess) refetchAllowance(); }, [approveSuccess, refetchAllowance]);

  // ── Submit intent ────────────────────────────────────────────────────────
  const {
    writeContract: submitIntent,
    data: submitTxHash,
    isPending: submitLoading,
  } = useWriteContract();
  const { isSuccess: submitSuccess, isLoading: submitConfirming } =
    useWaitForTransactionReceipt({ hash: submitTxHash });

  React.useEffect(() => {
    if (submitSuccess) {
      // nextId was the id just assigned (nextId - 1 after the tx)
      setIntentId((Number(nextId) - 1).toString());
      setAmountIn(""); setMinOut("");
    }
  }, [submitSuccess, nextId]);

  // ── Cancel intent ────────────────────────────────────────────────────────
  const {
    writeContract: cancelIntent,
    data: cancelTxHash,
    isPending: cancelLoading,
  } = useWriteContract();
  const { isSuccess: cancelSuccess, isLoading: cancelConfirming } =
    useWaitForTransactionReceipt({ hash: cancelTxHash });

  const [cancelIdInput, setCancelIdInput] = useState("");

  // ── Intent lookup ────────────────────────────────────────────────────────
  const [lookupId, setLookupId] = useState("");
  const parsedLookupId = lookupId && /^\d+$/.test(lookupId)
    ? BigInt(lookupId)
    : undefined;

  const { data: intentData, isLoading: intentLoading } = useReadContract({
    address:      SETTLEMENT_ENGINE_ADDRESS,
    abi:          SETTLEMENT_ENGINE_ABI,
    functionName: "getIntent",
    args:         parsedLookupId !== undefined ? [parsedLookupId] : undefined,
    query:        { enabled: !!SETTLEMENT_ENGINE_ADDRESS && parsedLookupId !== undefined },
  });

  const needsApproval =
    amountIn && parseFloat(amountIn) > 0 && allowance < parseUnits(amountIn || "0", 18);

  const txBusy = approveLoading || approveConfirming || submitLoading || submitConfirming || cancelLoading || cancelConfirming;

  const handleApprove = () => {
    if (!SETTLEMENT_ENGINE_ADDRESS) return;
    approve({ address: tokenInAddr, abi: ERC20_ABI, functionName: "approve", args: [SETTLEMENT_ENGINE_ADDRESS, maxUint256] });
  };

  const handleSubmit = () => {
    if (!SETTLEMENT_ENGINE_ADDRESS || !address) return;
    const amtIn  = parseUnits(amountIn, 18);
    const minAmt = minOut
      ? parseUnits(minOut, 18)
      : (amtIn * BigInt(Math.floor((1 - parseFloat(slippage) / 100) * 10_000))) / 10_000n;

    submitIntent({
      address:      SETTLEMENT_ENGINE_ADDRESS,
      abi:          SETTLEMENT_ENGINE_ABI,
      functionName: "submitIntent",
      args:         [tokenInAddr, tokenOutAddr, amtIn, minAmt, defaultDeadline()],
    });
  };

  const handleCancel = (id: string) => {
    if (!SETTLEMENT_ENGINE_ADDRESS) return;
    cancelIntent({
      address:      SETTLEMENT_ENGINE_ADDRESS,
      abi:          SETTLEMENT_ENGINE_ABI,
      functionName: "cancelIntent",
      args:         [BigInt(id)],
    });
  };

  // ── Not deployed guard ───────────────────────────────────────────────────
  if (!SETTLEMENT_ENGINE_ADDRESS) {
    return (
      <div className="max-w-md mx-auto">
        <Card>
          <CardContent className="py-12 text-center space-y-3">
            <Clock className="mx-auto h-10 w-10 text-kaia-muted/40" />
            <p className="text-kaia-text font-semibold">Settlement Engine</p>
            <p className="text-xs text-kaia-muted max-w-xs mx-auto">
              The SettlementEngine contract is not yet deployed on this network.
              Set <code className="bg-kaia-surface px-1 rounded">NEXT_PUBLIC_SETTLEMENT_ENGINE_ADDRESS</code> in your environment to enable intent-based netting.
            </p>
            <Badge variant="secondary" className="text-xs">Coming Soon</Badge>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-md mx-auto">
      {/* ── Submit Intent ─────────────────────────────────────────────── */}
      <Card>
        <CardContent className="pt-5 space-y-4">
          <div className="flex items-center gap-2">
            <PlusCircle className="h-4 w-4 text-kaia-primary" />
            <h3 className="font-bold text-kaia-text">Submit Swap Intent</h3>
          </div>
          <p className="text-xs text-kaia-muted">
            Intents are queued for netting. Matching buy/sell orders are settled
            off-pool — saving fees and reducing slippage for both parties.
          </p>

          {/* Token pair */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="text-xs text-kaia-muted">Sell</label>
              <TokenSelector value={tokenIn} onChange={(s) => { if (s === tokenOut) setTokenOut(tokenIn); setTokenIn(s); }} exclude={tokenOut} />
            </div>
            <div className="space-y-1">
              <label className="text-xs text-kaia-muted">Buy</label>
              <TokenSelector value={tokenOut} onChange={(s) => { if (s === tokenIn) setTokenIn(tokenOut); setTokenOut(s); }} exclude={tokenIn} />
            </div>
          </div>

          {/* Amount */}
          <div className="rounded-xl border border-kaia-border bg-kaia-surface p-4 space-y-2 focus-within:border-kaia-primary/60 transition-colors">
            <div className="flex justify-between text-xs text-kaia-muted">
              <span>Amount to sell ({tokenIn})</span>
            </div>
            <Input
              type="text" inputMode="decimal" placeholder="0.00"
              value={amountIn}
              onChange={(e) => { if (/^\d*\.?\d*$/.test(e.target.value)) setAmountIn(e.target.value); }}
              className="border-0 bg-transparent text-xl font-semibold p-0 focus-visible:ring-0"
            />
          </div>

          {/* Slippage / min out */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="text-xs text-kaia-muted">Slippage %</label>
              <input
                type="number"
                value={slippage}
                onChange={(e) => setSlippage(e.target.value)}
                className="w-full rounded-lg border border-kaia-border bg-kaia-surface px-3 py-2 text-sm text-kaia-text focus:outline-none focus:border-kaia-primary"
                step="0.1" min="0.1" max="10"
              />
            </div>
            <div className="space-y-1.5">
              <label className="text-xs text-kaia-muted">Min {tokenOut} (optional)</label>
              <Input
                type="text" inputMode="decimal" placeholder="auto"
                value={minOut}
                onChange={(e) => { if (/^\d*\.?\d*$/.test(e.target.value)) setMinOut(e.target.value); }}
                className="text-sm"
              />
            </div>
          </div>

          <div className="flex items-start gap-1.5 text-xs text-kaia-muted rounded-xl border border-kaia-border/50 bg-kaia-surface/40 px-3 py-2">
            <Info className="h-3.5 w-3.5 mt-0.5 shrink-0" />
            <span>Intents expire in 7 days. You can cancel at any time before settlement.</span>
          </div>

          {submitSuccess && intentId && (
            <div className="flex items-center gap-2 rounded-xl border border-kaia-primary/30 bg-kaia-primary/10 px-3 py-2 text-xs text-kaia-primary">
              <CheckCircle2 className="h-3.5 w-3.5" />
              Intent #{intentId} submitted successfully!
            </div>
          )}

          {!isConnected ? (
            <Button variant="secondary" className="w-full" disabled>Connect Wallet</Button>
          ) : needsApproval ? (
            <Button className="w-full" onClick={handleApprove} disabled={txBusy}>
              {approveLoading || approveConfirming
                ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Approving...</>
                : `Approve ${tokenIn}`}
            </Button>
          ) : (
            <Button
              className="w-full"
              onClick={handleSubmit}
              disabled={!amountIn || parseFloat(amountIn) <= 0 || txBusy}
            >
              {submitLoading || submitConfirming
                ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Submitting Intent...</>
                : <>Submit Intent {tokenFlag(tokenIn)} <ArrowRight className="mx-1 h-3.5 w-3.5" /> {tokenFlag(tokenOut)}</>}
            </Button>
          )}
        </CardContent>
      </Card>

      {/* ── Look Up / Cancel Intent ─────────────────────────────────────── */}
      <Card>
        <CardContent className="pt-5 space-y-4">
          <div className="flex items-center gap-2">
            <Clock className="h-4 w-4 text-kaia-primary" />
            <h3 className="font-bold text-kaia-text">Look Up / Cancel Intent</h3>
          </div>

          <div className="flex gap-2">
            <Input
              type="number"
              placeholder="Intent ID"
              value={lookupId}
              onChange={(e) => setLookupId(e.target.value)}
              className="flex-1 text-sm"
            />
          </div>

          {intentLoading && (
            <div className="flex items-center gap-2 text-xs text-kaia-muted">
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading...
            </div>
          )}

          {intentData && parsedLookupId !== undefined && (
            <IntentCard
              id={lookupId}
              data={intentData}
              onCancel={handleCancel}
              cancelLoading={cancelLoading || cancelConfirming}
              cancelSuccess={cancelSuccess}
              isOwner={address?.toLowerCase() === intentData[0].toLowerCase()}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function IntentCard({
  id,
  data,
  onCancel,
  cancelLoading,
  cancelSuccess,
  isOwner,
}: {
  id: string;
  data: readonly [string, string, string, bigint, bigint, bigint, boolean, boolean];
  onCancel: (id: string) => void;
  cancelLoading: boolean;
  cancelSuccess: boolean;
  isOwner: boolean;
}) {
  const [trader, tokenIn, tokenOut, amountIn, minAmountOut, deadline, settled, cancelled] = data;

  const tokenInSymbol  = TOKENS.find((t) => t.address.toLowerCase() === tokenIn.toLowerCase())?.symbol  ?? tokenIn.slice(0, 6);
  const tokenOutSymbol = TOKENS.find((t) => t.address.toLowerCase() === tokenOut.toLowerCase())?.symbol ?? tokenOut.slice(0, 6);

  const deadlineDate = new Date(Number(deadline) * 1000).toLocaleDateString("en-US", {
    month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit",
  });

  const statusBadge = cancelled
    ? <Badge variant="destructive" className="text-xs">Cancelled</Badge>
    : settled
    ? <Badge className="text-xs bg-kaia-primary/20 text-kaia-primary border-kaia-primary/30">Settled</Badge>
    : <Badge variant="secondary" className="text-xs">Pending</Badge>;

  return (
    <div className="rounded-xl border border-kaia-border bg-kaia-surface p-4 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-mono text-kaia-muted">Intent #{id}</span>
        {statusBadge}
      </div>

      <div className="flex items-center gap-2 text-sm font-semibold text-kaia-text">
        <span>{tokenFlag(tokenInSymbol)} {parseFloat(formatUnits(amountIn, 18)).toLocaleString("en-US", { maximumFractionDigits: 4 })} {tokenInSymbol}</span>
        <ArrowRight className="h-4 w-4 text-kaia-muted" />
        <span>{tokenFlag(tokenOutSymbol)} min {parseFloat(formatUnits(minAmountOut, 18)).toLocaleString("en-US", { maximumFractionDigits: 4 })} {tokenOutSymbol}</span>
      </div>

      <div className="text-xs text-kaia-muted space-y-1">
        <div className="flex justify-between">
          <span>Trader</span>
          <span className="font-mono">{trader.slice(0, 8)}...{trader.slice(-4)}</span>
        </div>
        <div className="flex justify-between">
          <span>Expires</span>
          <span>{deadlineDate}</span>
        </div>
      </div>

      {cancelSuccess && (
        <div className="flex items-center gap-2 text-xs text-kaia-primary">
          <CheckCircle2 className="h-3.5 w-3.5" /> Intent cancelled.
        </div>
      )}

      {!settled && !cancelled && isOwner && (
        <Button
          variant="outline"
          size="sm"
          className="w-full gap-1.5 text-red-400 border-red-500/30 hover:bg-red-500/10"
          onClick={() => onCancel(id)}
          disabled={cancelLoading}
        >
          {cancelLoading
            ? <><Loader2 className="h-3.5 w-3.5 animate-spin" /> Cancelling...</>
            : <><XCircle className="h-3.5 w-3.5" /> Cancel Intent</>}
        </Button>
      )}
    </div>
  );
}
