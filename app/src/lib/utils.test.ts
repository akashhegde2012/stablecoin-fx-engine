import { describe, expect, it } from "vitest";
import { cn, formatAmount, formatFee, formatPrice, shortenAddress } from "./utils";

describe("utils", () => {
  it("merges conditional and conflicting tailwind classes", () => {
    expect(cn("px-2 text-sm", false && "hidden", "px-4")).toContain("px-4");
    expect(cn("px-2 text-sm", false && "hidden", "px-4")).not.toContain("px-2");
  });

  it("formats token amounts with zero and tiny value handling", () => {
    expect(formatAmount(0n)).toBe("0");
    expect(formatAmount(1n)).toBe("< 0.0001");
    expect(formatAmount(1234567890000000000000n)).toBe("1,234.5679");
    expect(formatAmount(123456789n, 6, 3)).toBe("123.457");
  });

  it("formats oracle prices and basis points", () => {
    expect(formatPrice(74190000n)).toBe("$0.7419");
    expect(formatFee(30n)).toBe("0.30%");
  });

  it("shortens addresses for display", () => {
    expect(shortenAddress("0x1234567890abcdef1234567890abcdef12345678")).toBe("0x1234...5678");
  });
});
