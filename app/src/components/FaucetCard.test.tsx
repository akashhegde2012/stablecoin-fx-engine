import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { FaucetCard } from "./FaucetCard";

const refresh = vi.fn();
const requestTestTokens = vi.fn();
const useAccount = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh }),
}));

vi.mock("wagmi", () => ({
  useAccount: () => useAccount(),
}));

vi.mock("@/app/actions/faucet", () => ({
  requestTestTokens: (...args: unknown[]) => requestTestTokens(...args),
}));

describe("FaucetCard", () => {
  beforeEach(() => {
    refresh.mockClear();
    requestTestTokens.mockReset();
    useAccount.mockReturnValue({
      address: "0x00000000000000000000000000000000000000aa",
      isConnected: true,
    });
  });

  it("disables the faucet until a wallet is connected", () => {
    useAccount.mockReturnValue({ address: undefined, isConnected: false });

    render(<FaucetCard />);

    expect(screen.getByRole("button", { name: /connect wallet/i })).toBeDisabled();
    expect(screen.getByText("MYR")).toBeInTheDocument();
    expect(screen.getByText("10,000")).toBeInTheDocument();
  });

  it("requests tokens and renders submitted transaction links", async () => {
    requestTestTokens.mockResolvedValue({
      success: true,
      hashes: { MYR: "0x1234567890abcdef" },
    });

    render(<FaucetCard />);
    fireEvent.click(screen.getByRole("button", { name: /request test tokens/i }));

    await waitFor(() => {
      expect(requestTestTokens).toHaveBeenCalledWith("0x00000000000000000000000000000000000000aa");
    });
    expect(await screen.findByText(/tokens minted/i)).toBeInTheDocument();
    expect(screen.getByRole("link")).toHaveAttribute(
      "href",
      "https://kairos.kaiascan.io/tx/0x1234567890abcdef",
    );
    expect(refresh).toHaveBeenCalled();
  });

  it("renders errors and partial successes", async () => {
    requestTestTokens.mockResolvedValue({
      success: false,
      hashes: { MYR: "0xabcdef1234567890" },
      error: "Failed to mint SGD: nonce too low",
    });

    render(<FaucetCard />);
    fireEvent.click(screen.getByRole("button", { name: /request test tokens/i }));

    expect(await screen.findByText("Failed to mint SGD: nonce too low")).toBeInTheDocument();
    expect(screen.getByText(/tokens minted/i)).toBeInTheDocument();
  });
});
