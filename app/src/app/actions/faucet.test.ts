import { beforeEach, describe, expect, it, vi } from "vitest";

const writeContract = vi.fn();
const createWalletClient = vi.fn(() => ({ writeContract }));
const privateKeyToAccount = vi.fn(() => ({ address: "0x00000000000000000000000000000000000000fa" }));

vi.mock("viem", async () => {
  const actual = await vi.importActual<typeof import("viem")>("viem");
  return {
    ...actual,
    createWalletClient,
    http: vi.fn((url: string) => ({ url })),
  };
});

vi.mock("viem/accounts", () => ({
  privateKeyToAccount,
}));

vi.mock("@/lib/viemClient", () => ({
  activeChain: { id: 31337, name: "Anvil" },
  rpcUrl: "http://127.0.0.1:8545",
}));

describe("faucet action", () => {
  beforeEach(() => {
    vi.resetModules();
    writeContract.mockReset();
    createWalletClient.mockClear();
    privateKeyToAccount.mockClear();
    privateKeyToAccount.mockReturnValue({ address: "0x00000000000000000000000000000000000000fa" });
    delete process.env.FAUCET_PRIVATE_KEY;
  });

  it("rejects requests when the faucet key is not configured", async () => {
    const { requestTestTokens } = await import("./faucet");

    await expect(requestTestTokens("0x00000000000000000000000000000000000000aa")).resolves.toEqual({
      success: false,
      error: "Faucet not configured on this server.",
    });
  });

  it("normalises the faucet key and mints all test tokens sequentially", async () => {
    process.env.FAUCET_PRIVATE_KEY = "1".repeat(64);
    writeContract
      .mockResolvedValueOnce("0xmyr")
      .mockResolvedValueOnce("0xsgd")
      .mockResolvedValueOnce("0xidrx")
      .mockResolvedValueOnce("0xusdt");

    const { requestTestTokens } = await import("./faucet");
    const result = await requestTestTokens("0x00000000000000000000000000000000000000aa");

    expect(privateKeyToAccount).toHaveBeenCalledWith(`0x${"1".repeat(64)}`);
    expect(writeContract).toHaveBeenCalledTimes(4);
    expect(result).toEqual({
      success: true,
      hashes: {
        MYR: "0xmyr",
        SGD: "0xsgd",
        IDRX: "0xidrx",
        USDT: "0xusdt",
      },
    });
  });

  it("returns partial hashes when one mint fails", async () => {
    process.env.FAUCET_PRIVATE_KEY = `0x${"1".repeat(64)}`;
    writeContract
      .mockResolvedValueOnce("0xmyr")
      .mockRejectedValueOnce(new Error("nonce too low"));

    const { requestTestTokens } = await import("./faucet");
    const result = await requestTestTokens("0x00000000000000000000000000000000000000aa");

    expect(result).toEqual({
      success: false,
      hashes: { MYR: "0xmyr" },
      error: "Failed to mint SGD: nonce too low",
    });
  });

  it("reports invalid faucet private key configuration", async () => {
    process.env.FAUCET_PRIVATE_KEY = "not-a-key";
    privateKeyToAccount.mockImplementationOnce(() => {
      throw new Error("invalid key");
    });

    const { requestTestTokens } = await import("./faucet");
    await expect(requestTestTokens("0x00000000000000000000000000000000000000aa")).resolves.toEqual({
      success: false,
      error: "Invalid faucet key configuration.",
    });
  });
});
