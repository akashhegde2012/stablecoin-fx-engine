import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { TokenSelector } from "./TokenSelector";

describe("TokenSelector", () => {
  it("renders selected token and emits token changes", async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();

    render(<TokenSelector value="MYR" onChange={onChange} exclude="SGD" />);

    expect(screen.getByRole("combobox")).toHaveTextContent("MYR");

    await user.click(screen.getByRole("combobox"));
    await user.click(screen.getByRole("option", { name: /USDT/i }));

    expect(onChange).toHaveBeenCalledWith("USDT");
    expect(screen.queryByRole("option", { name: /SGD/i })).not.toBeInTheDocument();
  });
});
