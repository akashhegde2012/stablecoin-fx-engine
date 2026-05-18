import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { Header } from "./Header";

vi.mock("@rainbow-me/rainbowkit", () => ({
  ConnectButton: (props: Record<string, unknown>) => (
    <button data-account-status={props.accountStatus as string} data-chain-status={props.chainStatus as string}>
      Connect Wallet
    </button>
  ),
}));

describe("Header", () => {
  it("renders branding, network badge, and wallet control", () => {
    render(<Header />);

    expect(screen.getByText("KAIA")).toBeInTheDocument();
    expect(screen.getByText("FX")).toBeInTheDocument();
    expect(screen.getByText("Testnet")).toBeInTheDocument();

    const wallet = screen.getByRole("button", { name: "Connect Wallet" });
    expect(wallet).toHaveAttribute("data-account-status", "avatar");
    expect(wallet).toHaveAttribute("data-chain-status", "icon");
  });
});
