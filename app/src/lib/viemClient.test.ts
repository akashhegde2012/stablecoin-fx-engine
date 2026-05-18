import { describe, expect, it } from "vitest";
import { activeChain, anvilChain, kairosChain, rpcUrl } from "./viemClient";

describe("viemClient config", () => {
  it("defines local and Kairos chains", () => {
    expect(anvilChain.id).toBe(31337);
    expect(kairosChain.id).toBe(1001);
    expect(kairosChain.testnet).toBe(true);
  });

  it("uses the configured local chain by default in tests", () => {
    expect(activeChain.id).toBe(31337);
    expect(rpcUrl).toBe("http://127.0.0.1:8545");
  });
});
