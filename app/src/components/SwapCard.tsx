"use client";

import React, { useState, useTransition, useCallback, useEffect } from "react";
import {
  ArrowDownUp,
  AlertCircle,
  Loader2,
  CheckCircle2,
  Info,
} from "lucide-react";
import { parseUnits, maxUint256 } from "viem";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";

import { Button }        from "@/components/ui/button";
import { Input }         from "@/components/ui/input";
import { Card, CardContent } from "@/components/ui/card";
import { Separator }     from "@/components/ui/separator";
import { Skeleton }      from "@/components/ui/skeleton";
import { TokenSelector } from "@/components/TokenSelector";
import { getSwapQuote }  from "@/app/actions/quote";
import { TOKENS, TOKEN_ADDRESSES, POOL_ADDRESSES, FXENGINE_ADDRESS, FXENGINE_ABI, ERC20_ABI, FXPOOL_ABI, SETTLEMENT_ENGINE_ADDRESS, SETTLEMENT_ENGINE_ABI } from "@/lib/contracts";
import { useRouter } from "next/navigation";
import { formatAmount }  from "@/lib/utils";
import type { TokenSymbol } from "@/lib/contracts";

export function SwapCard() {
  const { address, isConnected } = useAccount();
  const router = useRouter();

  const [tokenIn,  setTokenIn]  = useState<TokenSymbol>("MYR");
  const [tokenOut, setTokenOut] = useState<TokenSymbol>("SGD");
  const [amountIn, setAmountIn] = useState("");
  const [slippage,  setSlippage]  = useState("0.5");

  const [quote,       setQuote]       = useState<string>("");
  const [quoteRaw,    setQuoteRaw]    = useState<bigint>(0n);
  const [rateDisplay, setRateDisplay] = useState<string>("");
  const [quoteError,  setQuoteError]  = useState<string>("");
  const [isPending,   startTransition] = useTransition();

  const tokenInAddr  = TOKEN_ADDRESSES[tokenIn  as keyof typeof TOKEN_ADDRESSES];
  const tokenOutAddr = TOKEN_ADDRESSES[tokenOut as keyof typeof TOKEN_ADDRESSES];
  const poolOutAddr = POOL_ADDRESSES[tokenOut as keyof typeof POOL_ADDRESSES];

  // ── Read allowance ──────────────────────────────────────────────────────────
  const { data: allowance = 0n, refetch: refetchAllowance } = useReadContract({
    address:      tokenInAddr,
    abi:          ERC20_ABI,
    functionName: "allowance",
    args:         address ? [address, FXENGINE_ADDRESS] : undefined,
    query:        { enabled: !!address },
  });

  // ── Read tokenIn balance ────────────────────────────────────────────────────
  const { data: balance = 0n, refetch: refetchBalance } = useReadContract({
    address:      tokenInAddr,
    abi:          ERC20_ABI,
    functionName: "balanceOf",
    args:         address ? [address] : undefined,
    query:        { enabled: !!address },
  });

  // ── Read effective fee rate for current quote ─────────────────────────────────
  const { data: effectiveFeeBps } = useReadContract({
    address:      poolOutAddr,
    abi:          FXPOOL_ABI,
    functionName: "getEffectiveFeeRate",
    args:         quoteRaw > 0n ? [quoteRaw] : undefined,
    query:        { enabled: quoteRaw > 0n },
  });
  const feeDisplay = effectiveFeeBps != null
    ? `${(Number(effectiveFeeBps) / 100).toFixed(2)}%`
    : null;

  // ── Read platform fee bps from out pool ────────────────────────────────────
  const { data: platformFeeBps = 0n } = useReadContract({
    address:      poolOutAddr,
    abi:          FXPOOL_ABI,
    functionName: "platformFeeBps",
    query:        { enabled: true },
  });
  const lpFeePct       = 100 - Number(platformFeeBps) / 100;
  const platformFeePct = Number(platformFeeBps) / 100;

  // ── Derived: min received ──────────────────────────────────────────────────
  const minReceived = quoteRaw > 0n
    ? (quoteRaw * BigInt(Math.floor((1 - parseFloat(slippage) / 100) * 10_000))) / 10_000n
    : 0n;

  // ── Write: approve ──────────────────────────────────────────────────────────
  const {
    writeContract: approve,
    data: approveTxHash,
    isPending: approveLoading,
  } = useWriteContract();

  const { isLoading: approveConfirming, isSuccess: approveSuccess } =
    useWaitForTransactionReceipt({ hash: approveTxHash });

  React.useEffect(() => {
    if (approveSuccess) refetchAllowance();
  }, [approveSuccess, refetchAllowance]);

  // ── Write: swap ─────────────────────────────────────────────────────────────
  const {
    writeContract: swap,
    data: swapTxHash,
    isPending: swapLoading,
  } = useWriteContract();

  const { isLoading: swapConfirming, isSuccess: swapSuccess } =
    useWaitForTransactionReceipt({ hash: swapTxHash });

  useEffect(() => {
    if (swapSuccess) {
      refetchBalance();
      refetchAllowance();
      setAmountIn("");
      setQuote(""); setQuoteRaw(0n); setRateDisplay("");
      router.refresh();
    }
  }, [swapSuccess, refetchBalance, refetchAllowance, router]);

  // ── Quote fetching (server action) ─────────────────────────────────────────
  const fetchQuote = useCallback(
    (value: string, inSym: TokenSymbol, outSym: TokenSymbol) => {
      if (!value || parseFloat(value) <= 0) {
        setQuote(""); setQuoteRaw(0n); setRateDisplay(""); setQuoteError("");
        return;
      }
      const inAddr  = TOKEN_ADDRESSES[inSym  as keyof typeof TOKEN_ADDRESSES];
      const outAddr = TOKEN_ADDRESSES[outSym as keyof typeof TOKEN_ADDRESSES];
      startTransition(async () => {
        const res = await getSwapQuote(inAddr, outAddr, value, inSym, outSym);
        if (res.error) {
          setQuoteError(res.error);
          setQuote(""); setQuoteRaw(0n); setRateDisplay("");
        } else {
          setQuote(res.amountOut);
          setQuoteRaw(BigInt(res.amountOutRaw));
          setRateDisplay(res.rateDisplay);
          setQuoteError("");
        }
      });
    },
    [],
  );

  const handleAmountChange = (v: string) => {
    if (!/^\d*\.?\d*$/.test(v)) return;
    setAmountIn(v);
    fetchQuote(v, tokenIn, tokenOut);
  };

  const handleFlip = () => {
    const newIn  = tokenOut;
    const newOut = tokenIn;
    setTokenIn(newIn);
    setTokenOut(newOut);
    setAmountIn("");
    setQuote(""); setQuoteRaw(0n); setRateDisplay("");
  };

  const handleTokenInChange = (sym: TokenSymbol) => {
    if (sym === tokenOut) { setTokenOut(tokenIn); }
    setTokenIn(sym);
    setAmountIn("");
    setQuote(""); setQuoteRaw(0n);
  };

  const handleTokenOutChange = (sym: TokenSymbol) => {
    if (sym === tokenIn) { setTokenIn(tokenOut); }
    setTokenOut(sym);
    fetchQuote(amountIn, tokenIn, sym);
  };

  // ── Actions ─────────────────────────────────────────────────────────────────
  const needsApproval =
    amountIn && parseFloat(amountIn) > 0 && allowance < parseUnits(amountIn || "0", 18);

  const handleApprove = () => {
    approve({
      address:      tokenInAddr,
      abi:          ERC20_ABI,
      functionName: "approve",
      args:         [FXENGINE_ADDRESS, maxUint256],
    });
  };

  const [pythStatus, setPythStatus] = useState<string>("");

  const handleSwap = async () => {
    if (!address || !quoteRaw) return;
    const amtIn  = parseUnits(amountIn, 18);
    const minOut = (quoteRaw * BigInt(Math.floor((1 - parseFloat(slippage) / 100) * 10000))) / 10000n;

    // Use swap() directly — Orakl is the primary push oracle and already on-chain.
    // swapWithPythUpdate() triggers cross-validation between Orakl (testnet mock prices)
    // and Pyth (real market prices), which fails with "OA: price deviation too high".
    setPythStatus("");
    swap({
      address:      FXENGINE_ADDRESS,
      abi:          FXENGINE_ABI,
      functionName: "swap",
      args:         [tokenInAddr, tokenOutAddr, amtIn, minOut, address],
    });
  };

  const handleMaxBalance = () => {
    const maxStr = formatAmount(balance as bigint, 18, 6).replace(/,/g, "");
    setAmountIn(maxStr);
    fetchQuote(maxStr, tokenIn, tokenOut);
  };

  const isSwapReady = isConnected && amountIn && parseFloat(amountIn) > 0 && quote && !quoteError;
  const txPending   = approveLoading || approveConfirming || swapLoading || swapConfirming;

  return (
    <Card className="w-full max-w-md mx-auto shadow-2xl shadow-kaia-primary/5 border-kaia-border">
      {/* ── Header ─────────────────────────────────────────────── */}
      <CardContent className="pt-6 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-xl font-bold text-kaia-text">Swap</h2>
          {/* Slippage */}
          <div className="flex items-center gap-1.5 text-xs text-kaia-muted">
            <Info className="h-3.5 w-3.5" />
            <span>Slippage</span>
            <input
              type="number"
              value={slippage}
              onChange={(e) => setSlippage(e.target.value)}
              className="w-12 rounded-lg border border-kaia-border bg-kaia-surface px-1.5 py-0.5 text-center text-kaia-text focus:outline-none focus:border-kaia-primary"
              step="0.1"
              min="0.1"
              max="5"
            />
            <span>%</span>
          </div>
        </div>

        {/* ── You Pay ──────────────────────────────────────────── */}
        <div className="rounded-xl border border-kaia-border bg-kaia-surface p-4 space-y-2 focus-within:border-kaia-primary/60 transition-colors">
          <div className="flex items-center justify-between text-xs text-kaia-muted">
            <span>You Pay</span>
            {isConnected && (
              <button
                onClick={handleMaxBalance}
                className="hover:text-kaia-primary transition-colors"
              >
                Balance: {formatAmount(balance as bigint)}
              </button>
            )}
          </div>
          <div className="flex items-center gap-3">
            <TokenSelector
              value={tokenIn}
              onChange={handleTokenInChange}
              exclude={tokenOut}
            />
            <Input
              type="text"
              inputMode="decimal"
              placeholder="0.00"
              value={amountIn}
              onChange={(e) => handleAmountChange(e.target.value)}
              className="flex-1 border-0 bg-transparent text-right text-2xl font-semibold p-0 focus-visible:ring-0 text-kaia-text placeholder:text-kaia-text-dim/40"
            />
          </div>
        </div>

        {/* ── Flip button ───────────────────────────────────────── */}
        <div className="flex justify-center -my-1">
          <button
            onClick={handleFlip}
            className="flex h-9 w-9 items-center justify-center rounded-xl border border-kaia-border bg-kaia-card text-kaia-muted hover:border-kaia-primary/50 hover:text-kaia-primary hover:bg-kaia-hover transition-all"
          >
            <ArrowDownUp className="h-4 w-4" />
          </button>
        </div>

        {/* ── You Receive ───────────────────────────────────────── */}
        <div className="rounded-xl border border-kaia-border bg-kaia-surface p-4 space-y-2">
          <div className="flex items-center justify-between text-xs text-kaia-muted">
            <span>You Receive</span>
            {isPending && <Loader2 className="h-3.5 w-3.5 animate-spin text-kaia-primary" />}
          </div>
          <div className="flex items-center gap-3">
            <TokenSelector
              value={tokenOut}
              onChange={handleTokenOutChange}
              exclude={tokenIn}
            />
            {isPending ? (
              <Skeleton className="ml-auto h-8 w-28" />
            ) : (
              <p className="ml-auto text-2xl font-semibold text-kaia-text">
                {quote || <span className="text-kaia-text-dim/40">0.00</span>}
              </p>
            )}
          </div>
        </div>

        {/* ── Rate & Info ───────────────────────────────────────── */}
        {rateDisplay && (
          <div className="rounded-xl border border-kaia-border bg-kaia-surface/50 px-4 py-3 space-y-1.5 text-xs text-kaia-muted">
            <div className="flex justify-between">
              <span>Rate</span>
              <span className="text-kaia-text">{rateDisplay}</span>
            </div>
            <div className="flex justify-between">
              <span>Effective Fee</span>
              <span className="text-kaia-text">{feeDisplay ?? "—"}</span>
            </div>
            {feeDisplay && (
              <div className="flex justify-between">
                <span>Fee Distribution</span>
                <span className="text-kaia-text">
                  <span className="text-kaia-primary">{lpFeePct.toFixed(0)}% LPs</span>
                  {" / "}
                  <span>{platformFeePct.toFixed(0)}% platform</span>
                </span>
              </div>
            )}
            {minReceived > 0n && (
              <div className="flex justify-between">
                <span>Min Received</span>
                <span className="text-kaia-text font-medium">
                  {parseFloat(
                    (Number(minReceived) / 1e18).toFixed(6)
                  ).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 6 })}{" "}
                  {tokenOut}
                </span>
              </div>
            )}
            <div className="flex justify-between">
              <span>Slippage Tolerance</span>
              <span className="text-kaia-text">{slippage}%</span>
            </div>
          </div>
        )}

        {/* ── Error ─────────────────────────────────────────────── */}
        {quoteError && (
          <div className="flex items-start gap-2 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-xs text-red-400">
            <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            <span className="line-clamp-2">{quoteError}</span>
          </div>
        )}

        {/* ── Swap Success ──────────────────────────────────────── */}
        {swapSuccess && (
          <div className="flex items-center gap-2 rounded-xl border border-kaia-primary/30 bg-kaia-primary/10 px-4 py-3 text-xs text-kaia-primary">
            <CheckCircle2 className="h-4 w-4" />
            <span>Swap successful!</span>
          </div>
        )}

        <Separator className="my-1" />

        {/* ── Buttons ───────────────────────────────────────────── */}
        {!isConnected ? (
          <Button variant="secondary" className="w-full" disabled>
            Connect Wallet to Swap
          </Button>
        ) : needsApproval ? (
          <Button
            className="w-full"
            onClick={handleApprove}
            disabled={txPending}
          >
            {approveLoading || approveConfirming ? (
              <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Approving...</>
            ) : (
              `Approve ${tokenIn}`
            )}
          </Button>
        ) : (
          <Button
            className="w-full"
            onClick={handleSwap}
            disabled={!isSwapReady || txPending}
          >
            {swapLoading || swapConfirming ? (
              <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> {pythStatus || "Swapping..."}</>
            ) : (
              `Swap ${tokenIn} \u2192 ${tokenOut}`
            )}
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
