import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { formatUnits } from "viem";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Format a bigint token amount (18 decimals) to a readable string. */
export function formatAmount(amount: bigint, decimals = 18, digits = 4): string {
  const str = formatUnits(amount, decimals);
  const num = parseFloat(str);
  if (num === 0) return "0";
  if (num < 0.0001) return "< 0.0001";
  return num.toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: digits,
  });
}

/** Format a Chainlink price (8 decimals) to USD string. */
export function formatPrice(price: bigint, decimals = 8): string {
  const num = parseFloat(formatUnits(price, decimals));
  return num.toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 4,
    maximumFractionDigits: 6,
  });
}

/** Format basis points to a percentage string. */
export function formatFee(bps: bigint): string {
  return `${(Number(bps) / 100).toFixed(2)}%`;
}

/** Shorten an address for display. */
export function shortenAddress(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}
