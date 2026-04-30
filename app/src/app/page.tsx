import { Suspense }     from "react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Skeleton }     from "@/components/ui/skeleton";
import { SwapCard }     from "@/components/SwapCard";
import { PoolsGrid }    from "@/components/PoolsGrid";
import { LiquidityPanel } from "@/components/LiquidityPanel";
import { IntentsPanel }  from "@/components/IntentsPanel";
import { FaucetCard }    from "@/components/FaucetCard";

function PoolsSkeleton() {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {[...Array(4)].map((_, i) => (
        <Skeleton key={i} className="h-44 w-full rounded-2xl" />
      ))}
    </div>
  );
}

export default function HomePage() {
  return (
    <section className="mx-auto max-w-6xl px-4 py-10">
      {/* Hero */}
      <div className="mb-10 text-center space-y-2">
        <h1 className="text-4xl font-extrabold tracking-tight text-kaia-text">
          Stable Coins for{" "}
          <span className="text-kaia-primary">Foreign Exchange</span>
        </h1>
        <p className="text-kaia-muted max-w-xl mx-auto text-sm">
          Swap MYR, SGD, IDRX and USDT with deep on-chain liquidity,
          Trusted price feeds and instant settlement.
        </p>
      </div>

      <Tabs defaultValue="swap" className="w-full">
        <div className="flex justify-center mb-6">
          <TabsList>
            <TabsTrigger value="swap">Swap</TabsTrigger>
            <TabsTrigger value="pools">Pools</TabsTrigger>
            <TabsTrigger value="liquidity">Liquidity</TabsTrigger>
            <TabsTrigger value="intents">Intents</TabsTrigger>
            <TabsTrigger value="faucet">Faucet</TabsTrigger>
          </TabsList>
        </div>

        {/* ── Swap ──────────────────────────────────────── */}
        <TabsContent value="swap">
          <SwapCard />
        </TabsContent>

        {/* ── Pools ─────────────────────────────────────── */}
        <TabsContent value="pools">
          <Suspense fallback={<PoolsSkeleton />}>
            <PoolsGrid />
          </Suspense>
        </TabsContent>

        {/* ── Liquidity ─────────────────────────────────── */}
        <TabsContent value="liquidity">
          <LiquidityPanel />
        </TabsContent>

        {/* ── Intents ───────────────────────────────────── */}
        <TabsContent value="intents">
          <IntentsPanel />
        </TabsContent>

        {/* ── Faucet ────────────────────────────────────── */}
        <TabsContent value="faucet">
          <FaucetCard />
        </TabsContent>
      </Tabs>
    </section>
  );
}
