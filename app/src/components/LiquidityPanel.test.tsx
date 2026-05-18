import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { LiquidityPanel } from "./LiquidityPanel";

const mocks = vi.hoisted(() => ({
  refresh: vi.fn(),
  useAccount: vi.fn(),
  useReadContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
  writeContract: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mocks.refresh }),
}));

vi.mock("wagmi", () => ({
  useAccount: () => mocks.useAccount(),
  useReadContract: (config: unknown) => mocks.useReadContract(config),
  useWriteContract: () => ({
    writeContract: mocks.writeContract,
    data: undefined,
    isPending: false,
  }),
  useWaitForTransactionReceipt: (config: unknown) => mocks.useWaitForTransactionReceipt(config),
}));

vi.mock("@/components/TokenSelector", () => ({
  TokenSelector: ({ value, onChange }: { value: string; onChange: (value: string) => void }) => (
    <select aria-label="pool-token" value={value} onChange={(event) => onChange(event.target.value)}>
      {["MYR", "SGD", "IDRX", "USDT"].map((symbol) => (
        <option key={symbol} value={symbol}>
          {symbol}
        </option>
      ))}
    </select>
  ),
}));

describe("LiquidityPanel", () => {
  beforeEach(() => {
    mocks.refresh.mockClear();
    mocks.writeContract.mockReset();
    mocks.useAccount.mockReturnValue({
      address: "0x00000000000000000000000000000000000000aa",
      isConnected: true,
    });
    mocks.useWaitForTransactionReceipt.mockReturnValue({ isLoading: false, isSuccess: false });
    mocks.useReadContract.mockImplementation(({ functionName, address }) => {
      if (functionName === "balanceOf") {
        const value = String(address).endsWith("aa") ? 10000000000000000000n : 1000000000000000000000n;
        return { data: value, refetch: vi.fn() };
      }
      if (functionName === "lpToken") return { data: "0x00000000000000000000000000000000000000aa" };
      if (functionName === "allowance") return { data: 10n ** 30n, refetch: vi.fn() };
      if (functionName === "lpToStablecoinRate") return { data: 2000000000000000000n };
      if (functionName === "getPoolBalance") return { data: 50000000000000000000000n };
      if (functionName === "totalSupply") return { data: 1000000000000000000000n };
      return { data: 0n, refetch: vi.fn() };
    });
  });

  it("renders disconnected state and pool statistics", () => {
    mocks.useAccount.mockReturnValue({ address: undefined, isConnected: false });

    render(<LiquidityPanel />);

    expect(screen.getByText("Manage Liquidity")).toBeInTheDocument();
    expect(screen.getByText("50,000.00 MYR")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeDisabled();
    expect(screen.queryByText("Wallet (MYR)")).not.toBeInTheDocument();
  });

  it("renders wallet position and deposits without approval", async () => {
    const user = userEvent.setup();

    render(<LiquidityPanel />);

    expect(screen.getByText("Your Position")).toBeInTheDocument();
    expect(screen.getByText("1.0000%")).toBeInTheDocument();
    expect(screen.getByText(/20.00\s+MYR/)).toBeInTheDocument();

    await user.type(screen.getByPlaceholderText("0.00"), "25");
    expect(screen.getByText(/12.5 wMYR LP tokens/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Deposit MYR" }));

    expect(mocks.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "deposit",
        args: [25000000000000000000n],
      }),
    );
  });

  it("requires approval when deposit allowance is too low", async () => {
    const user = userEvent.setup();
    mocks.useReadContract.mockImplementation(({ functionName }) => {
      if (functionName === "balanceOf") return { data: 1000000000000000000000n, refetch: vi.fn() };
      if (functionName === "lpToken") return { data: "0x00000000000000000000000000000000000000aa" };
      if (functionName === "allowance") return { data: 0n, refetch: vi.fn() };
      if (functionName === "lpToStablecoinRate") return { data: 1000000000000000000n };
      if (functionName === "getPoolBalance") return { data: 50000000000000000000000n };
      if (functionName === "totalSupply") return { data: 1000000000000000000000n };
      return { data: 0n, refetch: vi.fn() };
    });

    render(<LiquidityPanel />);
    await user.type(screen.getByPlaceholderText("0.00"), "100");
    fireEvent.click(screen.getByRole("button", { name: "Approve MYR" }));

    expect(mocks.writeContract).toHaveBeenCalledWith(expect.objectContaining({ functionName: "approve" }));
  });

  it("withdraws LP tokens from the withdraw tab", async () => {
    const user = userEvent.setup();

    render(<LiquidityPanel />);
    await user.click(screen.getByRole("tab", { name: /withdraw/i }));
    await user.type(screen.getByPlaceholderText("0.00"), "3");

    expect(screen.getByText(/6 MYR received/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Withdraw MYR" }));

    expect(mocks.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "withdraw",
        args: [3000000000000000000n],
      }),
    );
  });

  it("shows transaction success state and refreshes after receipts", async () => {
    mocks.useWaitForTransactionReceipt.mockReturnValue({ isLoading: false, isSuccess: true });

    render(<LiquidityPanel />);

    await waitFor(() => expect(mocks.refresh).toHaveBeenCalled());
    expect(screen.getByText("Deposit successful!")).toBeInTheDocument();
  });
});
