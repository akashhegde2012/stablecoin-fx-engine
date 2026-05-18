import { describe, expect, it, vi } from "vitest";

const getDefaultConfig = vi.fn((config) => ({ config }));

vi.mock("@rainbow-me/rainbowkit", () => ({
  getDefaultConfig: (config: unknown) => getDefaultConfig(config),
}));

describe("wagmiConfig", () => {
  it("creates RainbowKit config with app metadata and SSR enabled", async () => {
    const { wagmiConfig } = await import("./wagmiConfig");

    expect(getDefaultConfig).toHaveBeenCalledWith(
      expect.objectContaining({
        appName: "KAIA FX",
        projectId: "kaia-fx-dev",
        ssr: true,
      }),
    );
    expect(wagmiConfig.config.chains).toHaveLength(2);
    expect(wagmiConfig.config.chains.map((chain: { id: number }) => chain.id)).toEqual([1001, 31337]);
  });
});
