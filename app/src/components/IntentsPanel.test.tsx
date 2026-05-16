import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { IntentsPanel } from "./IntentsPanel";

const mocks = vi.hoisted(() => ({
  useAccount: vi.fn(),
  useReadContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
  writeContract: vi.fn(),
}));

vi.mock("@/lib/contracts", async () => {
  const actual = await vi.importActual<typeof import("@/lib/contracts")>("@/lib/contracts");
  return {
    ...actual,
    SETTLEMENT_ENGINE_ADDRESS: "0x00000000000000000000000000000000000000ee",
  };
});

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
  TokenSelector: ({
    value,
    onChange,
    exclude,
  }: {
    value: string;
    onChange: (value: string) => void;
    exclude?: string;
  }) => (
    <select aria-label={`intent-token-${value}`} value={value} onChange={(event) => onChange(event.target.value)}>
      {["MYR", "SGD", "IDRX", "USDT"]
        .filter((symbol) => symbol !== exclude)
        .map((symbol) => (
          <option key={symbol} value={symbol}>
            {symbol}
          </option>
        ))}
    </select>
  ),
}));

describe("IntentsPanel", () => {
  beforeEach(() => {
    mocks.writeContract.mockReset();
    mocks.useAccount.mockReturnValue({
      address: "0x00000000000000000000000000000000000000aa",
      isConnected: true,
    });
    mocks.useWaitForTransactionReceipt.mockReturnValue({ isLoading: false, isSuccess: false });
    mocks.useReadContract.mockImplementation(({ functionName, args }) => {
      if (functionName === "allowance") return { data: 10n ** 30n, refetch: vi.fn() };
      if (functionName === "nextIntentId") return { data: 8n };
      if (functionName === "getIntent" && args) {
        return {
          data: [
            "0x00000000000000000000000000000000000000aa",
            "0x0000000000000000000000000000000000000001",
            "0x0000000000000000000000000000000000000002",
            100000000000000000000n,
            74000000000000000000n,
            2000000000n,
            false,
            false,
          ] as const,
          isLoading: false,
        };
      }
      return { data: undefined, isLoading: false, refetch: vi.fn() };
    });
  });

  it("renders disconnected submit state", () => {
    mocks.useAccount.mockReturnValue({ address: undefined, isConnected: false });

    render(<IntentsPanel />);

    expect(screen.getByText("Submit Swap Intent")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Connect Wallet" })).toBeDisabled();
  });

  it("submits an intent with auto min-out from slippage", async () => {
    const user = userEvent.setup();

    render(<IntentsPanel />);
    await user.type(screen.getByPlaceholderText("0.00"), "100");
    fireEvent.click(screen.getByRole("button", { name: /submit intent/i }));

    expect(mocks.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "submitIntent",
        args: expect.arrayContaining([
          "0x0000000000000000000000000000000000000001",
          "0x0000000000000000000000000000000000000002",
          100000000000000000000n,
          99000000000000000000n,
        ]),
      }),
    );
  });

  it("requires token approval when allowance is low", async () => {
    const user = userEvent.setup();
    mocks.useReadContract.mockImplementation(({ functionName }) => {
      if (functionName === "allowance") return { data: 0n, refetch: vi.fn() };
      if (functionName === "nextIntentId") return { data: 8n };
      return { data: undefined, isLoading: false, refetch: vi.fn() };
    });

    render(<IntentsPanel />);
    await user.type(screen.getByPlaceholderText("0.00"), "100");
    fireEvent.click(screen.getByRole("button", { name: "Approve MYR" }));

    expect(mocks.writeContract).toHaveBeenCalledWith(expect.objectContaining({ functionName: "approve" }));
  });

  it("looks up an active owner intent and cancels it", async () => {
    const user = userEvent.setup();

    render(<IntentsPanel />);
    await user.type(screen.getByPlaceholderText("Intent ID"), "7");

    expect(await screen.findByText("Intent #7")).toBeInTheDocument();
    expect(screen.getByText("Pending")).toBeInTheDocument();
    expect(screen.getByText(/100 MYR/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /cancel intent/i }));
    expect(mocks.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "cancelIntent",
        args: [7n],
      }),
    );
  });

  it("shows submit success intent id from nextId", async () => {
    mocks.useWaitForTransactionReceipt.mockReturnValue({ isLoading: false, isSuccess: true });

    render(<IntentsPanel />);

    await waitFor(() => {
      expect(screen.getByText("Intent #7 submitted successfully!")).toBeInTheDocument();
    });
  });
});
