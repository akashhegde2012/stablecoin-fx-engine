import { beforeEach, describe, expect, it, vi } from "vitest";

const readContract = vi.fn();

vi.mock("@/lib/viemClient", () => ({
  publicClient: { readContract },
}));

describe("quote actions", () => {
  beforeEach(() => {
    readContract.mockReset();
  });

  it("returns an empty quote for blank or non-positive input", async () => {
    const { getSwapQuote } = await import("./quote");

    await expect(
      getSwapQuote(
        "0x0000000000000000000000000000000000000001",
        "0x0000000000000000000000000000000000000002",
        "0",
        "MYR",
        "SGD",
      ),
    ).resolves.toEqual({ amountOut: "", amountOutRaw: "0", rateDisplay: "" });
    expect(readContract).not.toHaveBeenCalled();
  });

  it("formats swap quote and one-unit rate", async () => {
    readContract
      .mockResolvedValueOnce(742500000000000000000n)
      .mockResolvedValueOnce(742500000000000000n);

    const { getSwapQuote } = await import("./quote");
    const result = await getSwapQuote(
      "0x0000000000000000000000000000000000000001",
      "0x0000000000000000000000000000000000000002",
      "1000",
      "MYR",
      "SGD",
    );

    expect(result).toEqual({
      amountOut: "742.50",
      amountOutRaw: "742500000000000000000",
      rateDisplay: "1 MYR = 0.7425 SGD",
    });
    expect(readContract).toHaveBeenCalledTimes(2);
  });

  it("returns server action errors without throwing", async () => {
    readContract.mockRejectedValueOnce(new Error("quote unavailable"));

    const { getSwapQuote } = await import("./quote");
    const result = await getSwapQuote(
      "0x0000000000000000000000000000000000000001",
      "0x0000000000000000000000000000000000000002",
      "10",
      "MYR",
      "SGD",
    );

    expect(result).toMatchObject({
      amountOut: "",
      amountOutRaw: "0",
      rateDisplay: "",
      error: "quote unavailable",
    });
  });

  it("reads token balance and allowance with zero fallbacks", async () => {
    const { getAllowance, getUserTokenBalance } = await import("./quote");

    readContract.mockResolvedValueOnce(123n);
    await expect(
      getUserTokenBalance(
        "0x0000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000aa",
      ),
    ).resolves.toBe("123");

    readContract.mockRejectedValueOnce(new Error("rpc down"));
    await expect(
      getAllowance(
        "0x0000000000000000000000000000000000000001",
        "0x00000000000000000000000000000000000000aa",
        "0x00000000000000000000000000000000000000bb",
      ),
    ).resolves.toBe("0");
  });
});
