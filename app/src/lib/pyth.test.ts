import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  getLatestPriceUpdates: vi.fn(),
  readContract: vi.fn(),
  createPublicClient: vi.fn(),
}));

vi.mock("@pythnetwork/hermes-client", () => ({
  HermesClient: vi.fn(function HermesClient() {
    return {
      getLatestPriceUpdates: mocks.getLatestPriceUpdates,
    };
  }),
}));

vi.mock("viem", async () => {
  const actual = await vi.importActual<typeof import("viem")>("viem");
  return {
    ...actual,
    createPublicClient: mocks.createPublicClient,
    http: vi.fn(() => "http-transport"),
  };
});

describe("pyth helpers", () => {
  beforeEach(() => {
    vi.resetModules();
    mocks.getLatestPriceUpdates.mockReset();
    mocks.readContract.mockReset();
    mocks.createPublicClient.mockReset();
    mocks.createPublicClient.mockReturnValue({ readContract: mocks.readContract });
  });

  it("fetches encoded update data from Hermes", async () => {
    mocks.getLatestPriceUpdates.mockResolvedValue({ binary: { data: "abcd" } });

    const { fetchPythUpdateData } = await import("./pyth");

    await expect(fetchPythUpdateData()).resolves.toEqual(["0xabcd"]);
    expect(mocks.getLatestPriceUpdates).toHaveBeenCalledWith(expect.any(Array), { encoding: "hex" });
  });

  it("throws when Hermes returns no binary payload", async () => {
    mocks.getLatestPriceUpdates.mockResolvedValue({});

    const { fetchPythUpdateData } = await import("./pyth");

    await expect(fetchPythUpdateData()).rejects.toThrow("Failed to fetch Pyth price updates from Hermes");
  });

  it("reads the Pyth update fee from the public client", async () => {
    mocks.readContract.mockResolvedValue(123n);

    const { getPythUpdateFee } = await import("./pyth");

    await expect(getPythUpdateFee(["0xabcd"])).resolves.toBe(123n);
    expect(mocks.readContract).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "getUpdateFee",
        args: [["0xabcd"]],
      }),
    );
  });
});
