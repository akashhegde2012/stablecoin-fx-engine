import * as React from "react";
import { cn } from "@/lib/utils";

const Input = React.forwardRef<HTMLInputElement, React.ComponentProps<"input">>(
  ({ className, type, ...props }, ref) => {
    return (
      <input
        type={type}
        className={cn(
          "flex w-full rounded-xl border border-kaia-border bg-kaia-surface px-4 py-3 text-base text-kaia-text ring-offset-background",
          "placeholder:text-kaia-text-dim",
          "focus-visible:outline-none focus-visible:border-kaia-primary focus-visible:ring-1 focus-visible:ring-kaia-primary/50",
          "disabled:cursor-not-allowed disabled:opacity-50",
          "transition-colors",
          className,
        )}
        ref={ref}
        {...props}
      />
    );
  },
);
Input.displayName = "Input";

export { Input };
