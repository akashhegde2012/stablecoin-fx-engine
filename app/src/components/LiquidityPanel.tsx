"use client";

import React, { useState } from "react";
import { PlusCircle, MinusCircle, Loader2, CheckCircle2, TrendingUp } from "lucide-react";
import { parseUnits, maxUint256, formatUnits } from "viem";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";
import { useRouter } from "next/navigation";

import { Button }              from "@/components/ui/button";
import { Input }               from "@/components/ui/input";
import { Card, CardContent }   from "@/components/ui/card";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { TokenSelector }       from "@/components/TokenSelector";
import { TOKENS, TOKEN_ADDRESSES, POOL_ADDRESSES, FXPOOL_ABI, ERC20_ABI } from "@/lib/contracts";
import { formatAmount }        from "@/lib/utils";
import type { TokenSymbol }    from "@/lib/contracts";

const LP_TOTAL_SUPPLY_ABI = [
  { name: "totalSupply", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

export function LiquidityPanel() {
  const { address, isConnected } = useAccount();
  const router = useRouter();
  const [selectedToken, setSelectedToken] = useState<TokenSymbol>("MYR");
  const [depositAmt,    setDepositAmt]    = useState("");
  const [withdrawAmt,   setWithdrawAmt]   = useState("");

  const tokenAddr = TOKEN_ADDRESSES[selectedToken as keyof typeof TOKEN_ADDRESSES];
  const poolAddr  = POOL_ADDRESSES[selectedToken  as keyof typeof POOL_ADDRESSES];

  // ── Read balances ────────────────────────────────────────────────────────────
  const { data: tokenBal = 0n, refetch: refetchTokenBal } = useReadContract({
    address: tokenAddr, abi: ERC20_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!address },
  });

  const { data: lpAddr } = useReadContract({
    address: poolAddr, abi: FXPOOL_ABI, functionName: "lpToken",
  });

  const { data: lpBal = 0n, refetch: refetchLpBal } = useReadContract({
    address: lpAddr as `0x${string}` | undefined,
    abi: ERC20_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!lpAddr },
  });

  const { data: allowance = 0n, refetch: refetchAllowance } = useReadContract({
    address: tokenAddr, abi: ERC20_ABI, functionName: "allowance",
    args: address ? [address, poolAddr] : undefined,
    query: { enabled: !!address },
  });

  // ── Pool stats ───────────────────────────────────────────────────────────────
  const { data: lpRate = 0n } = useReadContract({
    address: poolAddr,
    abi:     FXPOOL_ABI,
    functionName: "lpToStablecoinRate",
  });

  const { data: poolBalance = 0n } = useReadContract({
    address: poolAddr,
    abi:     FXPOOL_ABI,
    functionName: "getPoolBalance",
  });

  const { data: lpTotalSupply = 0n } = useReadContract({
    address: lpAddr as `0x${string}` | undefined,
    abi:     LP_TOTAL_SUPPLY_ABI,
    functionName: "totalSupply",
    query: { enabled: !!lpAddr },
  });

  // Derived: underlying value = lpBal * lpRate / 1e18
  const underlyingValue = lpRate > 0n ? (lpBal * lpRate) / BigInt(1e18) : 0n;

  // Derived: pool share %
  const poolSharePct =
    lpTotalSupply > 0n
      ? ((lpBal * 10_000n) / lpTotalSupply).toString()
      : "0";
  const poolShareDisplay = `${(Number(poolSharePct) / 100).toFixed(4)}%`;

  // LP rate display: 1 wSYM = X SYM
  const lpRateDisplay = lpRate > 0n
    ? parseFloat(formatUnits(lpRate, 18)).toLocaleString("en-US", {
        minimumFractionDigits: 6,
        maximumFractionDigits: 8,
      })
    : "—";

  // Total pool TVL
  const tvlDisplay = poolBalance > 0n
    ? parseFloat(formatUnits(poolBalance, 18)).toLocaleString("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })
    : "0.00";

  // ── Approve ──────────────────────────────────────────────────────────────────
  const { writeContract: approve, data: approveTxHash, isPending: approveLoading } =
    useWriteContract();
  const { isSuccess: approveSuccess, isLoading: approveConfirming } =
    useWaitForTransactionReceipt({ hash: approveTxHash });
  React.useEffect(() => { if (approveSuccess) refetchAllowance(); }, [approveSuccess, refetchAllowance]);

  // ── Deposit ──────────────────────────────────────────────────────────────────
  const { writeContract: deposit, data: depositTxHash, isPending: depositLoading } =
    useWriteContract();
  const { isSuccess: depositSuccess, isLoading: depositConfirming } =
    useWaitForTransactionReceipt({ hash: depositTxHash });
  React.useEffect(() => {
    if (depositSuccess) { refetchLpBal(); refetchTokenBal(); setDepositAmt(""); router.refresh(); }
  }, [depositSuccess, refetchLpBal, refetchTokenBal, router]);

  // ── Withdraw ─────────────────────────────────────────────────────────────────
  const { writeContract: withdraw, data: withdrawTxHash, isPending: withdrawLoading } =
    useWriteContract();
  const { isSuccess: withdrawSuccess, isLoading: withdrawConfirming } =
    useWaitForTransactionReceipt({ hash: withdrawTxHash });
  React.useEffect(() => {
    if (withdrawSuccess) { refetchLpBal(); refetchTokenBal(); setWithdrawAmt(""); router.refresh(); }
  }, [withdrawSuccess, refetchLpBal, refetchTokenBal, router]);

  const needsApproval =
    depositAmt && parseFloat(depositAmt) > 0 && allowance < parseUnits(depositAmt || "0", 18);

  const txBusy = approveLoading || approveConfirming || depositLoading || depositConfirming || withdrawLoading || withdrawConfirming;

  const handleApprove  = () => approve({ address: tokenAddr, abi: ERC20_ABI, functionName: "approve", args: [poolAddr, maxUint256] });
  const handleDeposit  = () => deposit({ address: poolAddr, abi: FXPOOL_ABI, functionName: "deposit",  args: [parseUnits(depositAmt,  18)] });
  const handleWithdraw = () => withdraw({ address: poolAddr, abi: FXPOOL_ABI, functionName: "withdraw", args: [parseUnits(withdrawAmt, 18)] });

  return (
    <div className="space-y-4">
      <Card className="w-full max-w-md mx-auto">
        <h2 className="text-xl pl-6 pt-4 font-bold text-kaia-text">Manage Liquidity</h2>
        <CardContent className="pt-3 space-y-4">
          {/* Token selector */}
          <div className="space-y-1.5">
            <label className="text-xs text-kaia-muted font-medium">Pool</label>
            <TokenSelector value={selectedToken} onChange={setSelectedToken} />
          </div>

          {/* Pool stats */}
          <div className="rounded-xl border border-kaia-border bg-kaia-surface/50 px-4 py-3 space-y-2">
            <p className="text-xs font-medium text-kaia-muted">Pool Statistics</p>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-kaia-muted">Total Liquidity</span>
                <span className="text-kaia-text font-medium">{tvlDisplay} {selectedToken}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-kaia-muted">LP Rate</span>
                <span className="text-kaia-text font-medium">1 w{selectedToken} = {lpRateDisplay} {selectedToken}</span>
              </div>
            </div>
          </div>

          {/* Wallet balances */}
          {isConnected && (
            <div className="grid grid-cols-2 gap-3 text-xs">
              <div className="rounded-xl border border-kaia-border bg-kaia-surface p-3">
                <p className="text-kaia-muted mb-1">Wallet ({selectedToken})</p>
                <p className="font-semibold text-kaia-text">{formatAmount(tokenBal as bigint)}</p>
              </div>
              <div className="rounded-xl border border-kaia-border bg-kaia-surface p-3">
                <p className="text-kaia-muted mb-1">LP Balance (w{selectedToken})</p>
                <p className="font-semibold text-kaia-primary">{formatAmount(lpBal as bigint)}</p>
              </div>
            </div>
          )}

          {/* Your position */}
          {isConnected && lpBal > 0n && (
            <div className="rounded-xl border border-kaia-primary/20 bg-kaia-primary/5 px-4 py-3 space-y-1.5 text-xs">
              <div className="flex items-center gap-1.5 text-kaia-primary font-medium mb-1">
                <TrendingUp className="h-3.5 w-3.5" />
                <span>Your Position</span>
              </div>
              <div className="flex justify-between">
                <span className="text-kaia-muted">Pool Share</span>
                <span className="text-kaia-text font-medium">{poolShareDisplay}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-kaia-muted">Underlying Value</span>
                <span className="text-kaia-primary font-semibold">
                  {parseFloat(formatUnits(underlyingValue as bigint, 18)).toLocaleString("en-US", {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 4,
                  })}{" "}
                  {selectedToken}
                </span>
              </div>
            </div>
          )}

          <Tabs defaultValue="deposit" className="w-full">
            <TabsList className="w-full">
              <TabsTrigger value="deposit"  className="flex-1 gap-1.5"><PlusCircle  className="h-3.5 w-3.5" /> Deposit</TabsTrigger>
              <TabsTrigger value="withdraw" className="flex-1 gap-1.5"><MinusCircle className="h-3.5 w-3.5" /> Withdraw</TabsTrigger>
            </TabsList>

            {/* ── Deposit ─────────────────────────────────────────── */}
            <TabsContent value="deposit" className="space-y-3 mt-4">
              <div className="rounded-xl border border-kaia-border bg-kaia-surface p-4 space-y-2 focus-within:border-kaia-primary/60 transition-colors">
                <div className="flex justify-between text-xs text-kaia-muted">
                  <span>Amount ({selectedToken})</span>
                  {isConnected && (
                    <button
                      onClick={() => setDepositAmt(formatAmount(tokenBal as bigint, 18, 6).replace(/,/g, ""))}
                      className="hover:text-kaia-primary transition-colors"
                    >
                      Max
                    </button>
                  )}
                </div>
                <Input
                  type="text" inputMode="decimal" placeholder="0.00"
                  value={depositAmt}
                  onChange={(e) => { if (/^\d*\.?\d*$/.test(e.target.value)) setDepositAmt(e.target.value); }}
                  className="border-0 bg-transparent text-xl font-semibold p-0 focus-visible:ring-0"
                />
                {depositAmt && parseFloat(depositAmt) > 0 && lpRate > 0n && (
                  <p className="text-xs text-kaia-muted">
                    ≈ {(parseFloat(depositAmt) / parseFloat(formatUnits(lpRate, 18))).toLocaleString("en-US", { maximumFractionDigits: 4 })} w{selectedToken} LP tokens
                  </p>
                )}
              </div>

              {depositSuccess && (
                <div className="flex items-center gap-2 rounded-xl border border-kaia-primary/30 bg-kaia-primary/10 px-3 py-2 text-xs text-kaia-primary">
                  <CheckCircle2 className="h-3.5 w-3.5" /> Deposit successful!
                </div>
              )}

              {!isConnected ? (
                <Button variant="secondary" className="w-full" disabled>Connect Wallet</Button>
              ) : needsApproval ? (
                <Button className="w-full" onClick={handleApprove} disabled={txBusy}>
                  {approveLoading || approveConfirming
                    ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Approving...</>
                    : `Approve ${selectedToken}`}
                </Button>
              ) : (
                <Button className="w-full" onClick={handleDeposit} disabled={!depositAmt || txBusy}>
                  {depositLoading || depositConfirming
                    ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Depositing...</>
                    : `Deposit ${selectedToken}`}
                </Button>
              )}
            </TabsContent>

            {/* ── Withdraw ────────────────────────────────────────── */}
            <TabsContent value="withdraw" className="space-y-3 mt-4">
              <div className="rounded-xl border border-kaia-border bg-kaia-surface p-4 space-y-2 focus-within:border-kaia-primary/60 transition-colors">
                <div className="flex justify-between text-xs text-kaia-muted">
                  <span>LP Amount (w{selectedToken})</span>
                  {isConnected && (
                    <button
                      onClick={() => setWithdrawAmt(formatAmount(lpBal as bigint, 18, 6).replace(/,/g, ""))}
                      className="hover:text-kaia-primary transition-colors"
                    >
                      Max
                    </button>
                  )}
                </div>
                <Input
                  type="text" inputMode="decimal" placeholder="0.00"
                  value={withdrawAmt}
                  onChange={(e) => { if (/^\d*\.?\d*$/.test(e.target.value)) setWithdrawAmt(e.target.value); }}
                  className="border-0 bg-transparent text-xl font-semibold p-0 focus-visible:ring-0"
                />
                {withdrawAmt && parseFloat(withdrawAmt) > 0 && lpRate > 0n && (
                  <p className="text-xs text-kaia-muted">
                    ≈ {(parseFloat(withdrawAmt) * parseFloat(formatUnits(lpRate, 18))).toLocaleString("en-US", { maximumFractionDigits: 4 })} {selectedToken} received
                  </p>
                )}
              </div>

              {withdrawSuccess && (
                <div className="flex items-center gap-2 rounded-xl border border-kaia-primary/30 bg-kaia-primary/10 px-3 py-2 text-xs text-kaia-primary">
                  <CheckCircle2 className="h-3.5 w-3.5" /> Withdrawal successful!
                </div>
              )}

              {!isConnected ? (
                <Button variant="secondary" className="w-full" disabled>Connect Wallet</Button>
              ) : (
                <Button className="w-full" onClick={handleWithdraw} disabled={!withdrawAmt || txBusy} variant="outline">
                  {withdrawLoading || withdrawConfirming
                    ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Withdrawing...</>
                    : `Withdraw ${selectedToken}`}
                </Button>
              )}
            </TabsContent>
          </Tabs>
        </CardContent>
      </Card>
    </div>
  );
}
