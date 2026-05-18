import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { SwapCard } from "./SwapCard";

const mocks = vi.hoisted(() => ({
  refresh: vi.fn(),
  getSwapQuote: vi.fn(),
  useAccount: vi.fn(),
  useReadContract: vi.fn(),
  useWaitForTransactionReceipt: vi.fn(),
  writeContract: vi.fn(),
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mocks.refresh }),
}));

vi.mock("@/app/actions/quote", () => ({
  getSwapQuote: (...args: unknown[]) => mocks.getSwapQuote(...args),
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
  TokenSelector: ({
    value,
    onChange,
    exclude,
  }: {
    value: string;
    onChange: (value: string) => void;
    exclude?: string;
  }) => (
    <select aria-label={`token-${value}`} value={value} onChange={(event) => onChange(event.target.value)}>
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

describe("SwapCard", () => {
  beforeEach(() => {
    mocks.refresh.mockClear();
    mocks.getSwapQuote.mockReset();
    mocks.writeContract.mockReset();
    mocks.useAccount.mockReturnValue({
      address: "0x00000000000000000000000000000000000000aa",
      isConnected: true,
    });
    mocks.useWaitForTransactionReceipt.mockReturnValue({ isLoading: false, isSuccess: false });
    mocks.useReadContract.mockImplementation(({ functionName }) => {
      if (functionName === "allowance") return { data: 10n ** 30n, refetch: vi.fn() };
      if (functionName === "balanceOf") return { data: 123456000000000000000n, refetch: vi.fn() };
      if (functionName === "getEffectiveFeeRate") return { data: 45n };
      if (functionName === "platformFeeBps") return { data: 3000n };
      return { data: 0n, refetch: vi.fn() };
    });
  });

  it("renders disconnected state with disabled swap CTA", () => {
    mocks.useAccount.mockReturnValue({ address: undefined, isConnected: false });

    render(<SwapCard />);

    expect(screen.getByRole("button", { name: /connect wallet to swap/i })).toBeDisabled();
    expect(screen.getByText("Swap")).toBeInTheDocument();
    expect(screen.queryByText(/Balance:/)).not.toBeInTheDocument();
  });

  it("fetches a quote, displays derived fee details, and submits a swap", async () => {
    const user = userEvent.setup();
    mocks.getSwapQuote.mockResolvedValue({
      amountOut: "742.50",
      amountOutRaw: "742500000000000000000",
      rateDisplay: "1 MYR = 0.7425 SGD",
    });

    render(<SwapCard />);
    await user.type(screen.getByPlaceholderText("0.00"), "1000");

    expect(await screen.findByText("742.50")).toBeInTheDocument();
    expect(screen.getByText("1 MYR = 0.7425 SGD")).toBeInTheDocument();
    expect(screen.getByText("0.45%")).toBeInTheDocument();
    expect(screen.getByText(/70% LPs/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /swap myr/i }));

    await waitFor(() => {
      expect(mocks.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          functionName: "swap",
          args: expect.arrayContaining([1000000000000000000000n]),
        }),
      );
    });
  });

  it("routes to approval when allowance is too low", async () => {
    const user = userEvent.setup();
    mocks.useReadContract.mockImplementation(({ functionName }) => {
      if (functionName === "allowance") return { data: 0n, refetch: vi.fn() };
      if (functionName === "balanceOf") return { data: 100000000000000000000n, refetch: vi.fn() };
      if (functionName === "platformFeeBps") return { data: 3000n };
      return { data: 30n, refetch: vi.fn() };
    });
    mocks.getSwapQuote.mockResolvedValue({
      amountOut: "7.42",
      amountOutRaw: "7420000000000000000",
      rateDisplay: "1 MYR = 0.7420 SGD",
    });

    render(<SwapCard />);
    await user.type(screen.getByPlaceholderText("0.00"), "10");
    fireEvent.click(await screen.findByRole("button", { name: "Approve MYR" }));

    expect(mocks.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({
        functionName: "approve",
      }),
    );
  });

  it("shows quote errors and uses max balance", async () => {
    mocks.getSwapQuote.mockResolvedValue({
      amountOut: "",
      amountOutRaw: "0",
      rateDisplay: "",
      error: "quote unavailable",
    });

    render(<SwapCard />);
    fireEvent.click(screen.getByText(/Balance:/));

    expect(await screen.findByText("quote unavailable")).toBeInTheDocument();
    expect(screen.getByPlaceholderText("0.00")).toHaveValue("123.456");
  });

  it("shows success state from transaction receipt", () => {
    mocks.useWaitForTransactionReceipt.mockReturnValue({ isLoading: false, isSuccess: true });

    render(<SwapCard />);

    expect(screen.getByText("Swap successful!")).toBeInTheDocument();
    expect(mocks.refresh).toHaveBeenCalled();
  });
});
