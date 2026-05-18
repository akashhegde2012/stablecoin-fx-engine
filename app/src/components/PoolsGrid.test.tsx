import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PoolsGrid } from "./PoolsGrid";

const getAllPoolsInfo = vi.fn();

vi.mock("@/app/actions/pools", () => ({
  getAllPoolsInfo: () => getAllPoolsInfo(),
}));

describe("PoolsGrid", () => {
  beforeEach(() => {
    getAllPoolsInfo.mockReset();
  });

  it("renders pool count and pool stats from the server action", async () => {
    getAllPoolsInfo.mockResolvedValue([
      {
        symbol: "SGD",
        name: "Singapore Dollar",
        tokenAddress: "0x0000000000000000000000000000000000000002",
        poolAddress: "0x1234567890abcdef1234567890abcdef12345678",
        lpToken: "0x00000000000000000000000000000000000000aa",
        balance: "50,000.00",
        balanceRaw: "50000000000000000000000",
        feeRate: "0.30% – 1.00%",
        feeRateBps: "30",
        maxFeeBps: "100",
        platformFeeBps: "3000",
        platformFeeLabel: "30%",
        lpFeePct: "70%",
        utilizationFactor: "250",
        price: "$0.741900",
        priceSource: "Orakl",
        flag: "SG",
      },
    ]);

    render(await PoolsGrid());

    expect(screen.getByText("1 active pools")).toBeInTheDocument();
    expect(screen.getAllByText("SGD")).toHaveLength(2);
    expect(screen.getByText("Singapore Dollar")).toBeInTheDocument();
    expect(screen.getByText("$0.741900")).toBeInTheDocument();
    expect(screen.getByText("via Orakl")).toBeInTheDocument();
    expect(screen.getByText("50,000.00")).toBeInTheDocument();
    expect(screen.getByText("0.30% – 1.00%")).toBeInTheDocument();
    expect(screen.getByText("70% LPs")).toBeInTheDocument();
    expect(screen.getByText("0x12345678...345678")).toBeInTheDocument();
  });

  it("renders empty active pool count", async () => {
    getAllPoolsInfo.mockResolvedValue([]);

    render(await PoolsGrid());

    expect(screen.getByText("0 active pools")).toBeInTheDocument();
  });
});
