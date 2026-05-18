import { beforeEach, describe, expect, it, vi } from "vitest";

const readContract = vi.fn();

vi.mock("@/lib/viemClient", () => ({
  publicClient: { readContract },
}));

describe("pool actions", () => {
  beforeEach(() => {
    readContract.mockReset();
  });

  it("builds pool cards from independent pool and oracle reads", async () => {
    readContract.mockImplementation(({ functionName }) => {
      switch (functionName) {
        case "getPoolBalance":
          return Promise.resolve(1_000_000000000000000000n);
        case "feeRate":
          return Promise.resolve(30n);
        case "maxDynamicFeeRate":
          return Promise.resolve(100n);
        case "lpToken":
          return Promise.resolve("0x00000000000000000000000000000000000000aa");
        case "platformFeeBps":
          return Promise.resolve(3000n);
        case "utilizationFactor":
          return Promise.resolve(250n);
        case "getOraklPrice":
          return Promise.resolve([74190000n, 8]);
        default:
          throw new Error(`unexpected ${String(functionName)}`);
      }
    });

    const { getAllPoolsInfo } = await import("./pools");
    const pools = await getAllPoolsInfo();

    expect(pools).toHaveLength(4);
    expect(pools[0]).toMatchObject({
      symbol: "MYR",
      balance: "1,000.00",
      feeRate: "0.30% – 1.00%",
      platformFeeLabel: "30%",
      lpFeePct: "70%",
      utilizationFactor: "250",
      price: "$0.7419",
      priceSource: "Orakl",
    });
  });

  it("falls back to Pyth price and filters unreachable pools", async () => {
    readContract.mockImplementation(({ address, functionName }) => {
      if (functionName === "getPoolBalance") return Promise.resolve(0n);
      if (functionName === "feeRate") return Promise.resolve(0n);
      if (functionName === "maxDynamicFeeRate") return Promise.resolve(0n);
      if (functionName === "platformFeeBps") return Promise.resolve(0n);
      if (functionName === "utilizationFactor") return Promise.resolve(0n);
      if (functionName === "getOraklPrice") return Promise.reject(new Error("orakl down"));
      if (functionName === "getPythPrice") return Promise.resolve([100000000n, 8]);
      if (functionName === "lpToken") return Promise.resolve(address);
      throw new Error(`unexpected ${String(functionName)}`);
    });

    const { getAllPoolsInfo } = await import("./pools");
    await expect(getAllPoolsInfo()).resolves.toEqual([]);
  });

  it("computes user LP balances and drops failed pool reads", async () => {
    let lpTokenReads = 0;
    readContract.mockImplementation(({ functionName }) => {
      if (functionName === "lpToken") {
        lpTokenReads += 1;
        if (lpTokenReads === 2) throw new Error("pool unavailable");
        return Promise.resolve("0x00000000000000000000000000000000000000aa");
      }
      if (functionName === "balanceOf") return Promise.resolve(10000000000000000000n);
      if (functionName === "totalSupply") return Promise.resolve(100000000000000000000n);
      if (functionName === "getPoolBalance") return Promise.resolve(1000000000000000000000n);
      throw new Error(`unexpected ${String(functionName)}`);
    });

    const { getUserLPBalances } = await import("./pools");
    const balances = await getUserLPBalances("0x00000000000000000000000000000000000000aa");

    expect(balances).toHaveLength(3);
    expect(balances[0]).toMatchObject({
      symbol: "MYR",
      lpBalance: "10.0000",
      lpBalanceRaw: "10000000000000000000",
      underlying: "100.00",
    });
  });
});
