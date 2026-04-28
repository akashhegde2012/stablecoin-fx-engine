"use client";

import * as React from "react";
import * as SelectPrimitive from "@radix-ui/react-select";
import { ChevronDown, Check } from "lucide-react";
import { cn } from "@/lib/utils";
import { TOKENS } from "@/lib/contracts";
import type { TokenSymbol } from "@/lib/contracts";

const FLAG_EMOJI: Record<string, string> = {
  MY: "🇲🇾",
  SG: "🇸🇬",
  ID: "🇮🇩",
  US: "🇺🇸",
};

interface TokenSelectorProps {
  value: TokenSymbol;
  onChange: (v: TokenSymbol) => void;
  exclude?: TokenSymbol;
  className?: string;
}

export function TokenSelector({ value, onChange, exclude, className }: TokenSelectorProps) {
  const selected = TOKENS.find((t) => t.symbol === value)!;

  return (
    <SelectPrimitive.Root value={value} onValueChange={(v) => onChange(v as TokenSymbol)}>
      <SelectPrimitive.Trigger
        className={cn(
          "flex items-center gap-2 rounded-xl border border-kaia-border bg-kaia-surface px-3 py-2",
          "text-sm font-semibold text-kaia-text",
          "hover:border-kaia-primary/50 hover:bg-kaia-hover",
          "focus:outline-none focus:border-kaia-primary",
          "transition-colors min-w-[110px]",
          className,
        )}
      >
        <span className="text-lg leading-none">{FLAG_EMOJI[selected.flag]}</span>
        <span>{selected.symbol}</span>
        <ChevronDown className="ml-auto h-4 w-4 text-kaia-muted" />
      </SelectPrimitive.Trigger>

      <SelectPrimitive.Portal>
        <SelectPrimitive.Content
          className="z-50 min-w-[160px] overflow-hidden rounded-xl border border-kaia-border bg-kaia-card shadow-2xl shadow-black/50 backdrop-blur-sm"
          position="popper"
          sideOffset={6}
        >
          <SelectPrimitive.Viewport className="p-1">
            {TOKENS.filter((t) => t.symbol !== exclude).map((token) => (
              <SelectPrimitive.Item
                key={token.symbol}
                value={token.symbol}
                className={cn(
                  "flex cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2.5",
                  "text-sm text-kaia-text",
                  "hover:bg-kaia-hover focus:bg-kaia-hover focus:outline-none",
                  "data-[state=checked]:text-kaia-primary",
                  "transition-colors",
                )}
              >
                <span className="text-lg leading-none">{FLAG_EMOJI[token.flag]}</span>
                <div>
                  <SelectPrimitive.ItemText>
                    <span className="font-semibold">{token.symbol}</span>
                  </SelectPrimitive.ItemText>
                  <p className="text-xs text-kaia-muted">{token.name}</p>
                </div>
                <SelectPrimitive.ItemIndicator className="ml-auto">
                  <Check className="h-4 w-4 text-kaia-primary" />
                </SelectPrimitive.ItemIndicator>
              </SelectPrimitive.Item>
            ))}
          </SelectPrimitive.Viewport>
        </SelectPrimitive.Content>
      </SelectPrimitive.Portal>
    </SelectPrimitive.Root>
  );
}
