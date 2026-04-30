import { TrendingUp, Droplets, Percent, PieChart, Zap } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge }             from "@/components/ui/badge";
import { getAllPoolsInfo }   from "@/app/actions/pools";

const FLAG_EMOJI: Record<string, string> = {
  MY: "🇲🇾", SG: "🇸🇬", ID: "🇮🇩", US: "🇺🇸",
};

export async function PoolsGrid() {
  const pools = await getAllPoolsInfo();

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-bold text-kaia-text">Liquidity Pools</h2>
        <Badge variant="secondary" className="text-xs">
          {pools.length} active pools
        </Badge>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {pools.map((pool) => (
          <Card
            key={pool.symbol}
            className="group transition-all hover:border-kaia-primary/40 hover:shadow-lg hover:shadow-kaia-primary/5"
          >
            <CardContent className="p-5 space-y-4">
              {/* Token header */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <span className="text-3xl leading-none">{FLAG_EMOJI[pool.flag]}</span>
                  <div>
                    <p className="font-bold text-kaia-text">{pool.symbol}</p>
                    <p className="text-xs text-kaia-muted">{pool.name}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="text-lg font-bold text-kaia-primary">{pool.price}</p>
                  <p className="text-xs text-kaia-muted">
                    {pool.priceSource !== "—" ? `via ${pool.priceSource}` : "price unavailable"}
                  </p>
                </div>
              </div>

              {/* Stats row 1: liquidity + swap fee */}
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-xl border border-kaia-border bg-kaia-surface p-3">
                  <div className="flex items-center gap-1.5 text-xs text-kaia-muted mb-1">
                    <Droplets className="h-3.5 w-3.5" />
                    <span>Liquidity</span>
                  </div>
                  <p className="text-sm font-semibold text-kaia-text">
                    {pool.balance}
                  </p>
                  <p className="text-xs text-kaia-muted">{pool.symbol}</p>
                </div>

                <div className="rounded-xl border border-kaia-border bg-kaia-surface p-3">
                  <div className="flex items-center gap-1.5 text-xs text-kaia-muted mb-1">
                    <Percent className="h-3.5 w-3.5" />
                    <span>Swap Fee</span>
                  </div>
                  <p className="text-sm font-semibold text-kaia-primary">{pool.feeRate}</p>
                  <p className="text-xs text-kaia-muted">dynamic (utilization-based)</p>
                </div>
              </div>

              {/* Stats row 2: fee distribution + utilization scaling */}
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-xl border border-kaia-border bg-kaia-surface p-3">
                  <div className="flex items-center gap-1.5 text-xs text-kaia-muted mb-1">
                    <PieChart className="h-3.5 w-3.5" />
                    <span>Fee Split</span>
                  </div>
                  <div className="flex items-center gap-1.5 mt-0.5">
                    {/* LP bar */}
                    <div
                      className="h-2 rounded-full bg-kaia-primary"
                      style={{ width: pool.lpFeePct }}
                    />
                    <div
                      className="h-2 rounded-full bg-kaia-muted/40"
                      style={{ width: pool.platformFeeLabel }}
                    />
                  </div>
                  <p className="text-xs text-kaia-text mt-1">
                    <span className="text-kaia-primary font-medium">{pool.lpFeePct} LPs</span>
                    {" / "}
                    <span className="text-kaia-muted">{pool.platformFeeLabel} platform</span>
                  </p>
                </div>

                <div className="rounded-xl border border-kaia-border bg-kaia-surface p-3">
                  <div className="flex items-center gap-1.5 text-xs text-kaia-muted mb-1">
                    <Zap className="h-3.5 w-3.5" />
                    <span>Fee Scaling</span>
                  </div>
                  <p className="text-sm font-semibold text-kaia-text">
                    {(Number(pool.utilizationFactor) / 100).toFixed(0)}×
                  </p>
                  <p className="text-xs text-kaia-muted">utilization factor</p>
                </div>
              </div>

              {/* Address */}
              <div className="flex items-center gap-1.5 text-xs text-kaia-text-dim">
                <TrendingUp className="h-3.5 w-3.5 text-kaia-muted" />
                <span className="font-mono truncate text-kaia-muted">
                  {pool.poolAddress.slice(0, 10)}...{pool.poolAddress.slice(-6)}
                </span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Legend */}
      <p className="text-xs text-kaia-muted text-center">
        Fees scale with trade size · LP share accrues in-pool · Platform fee funds protocol development
      </p>
    </div>
  );
}
