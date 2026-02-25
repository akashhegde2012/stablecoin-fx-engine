import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-xl text-sm font-semibold ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-40 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default:
          "bg-kaia-primary text-kaia-bg hover:bg-kaia-primary-dim shadow-[0_0_16px_rgba(0,210,170,0.4)] hover:shadow-[0_0_24px_rgba(0,210,170,0.6)]",
        secondary:
          "bg-kaia-surface border border-kaia-border text-kaia-text hover:bg-kaia-hover hover:border-kaia-primary/50",
        outline:
          "border border-kaia-border bg-transparent text-kaia-text hover:bg-kaia-hover hover:border-kaia-primary/60",
        ghost:
          "text-kaia-muted hover:bg-kaia-hover hover:text-kaia-text",
        destructive:
          "bg-red-500/20 border border-red-500/40 text-red-400 hover:bg-red-500/30",
        link:
          "text-kaia-primary underline-offset-4 hover:underline p-0 h-auto",
      },
      size: {
        default: "h-11 px-5 py-2",
        sm:      "h-9 px-3 text-xs",
        lg:      "h-13 px-8 text-base",
        icon:    "h-10 w-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size:    "default",
    },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    );
  },
);
Button.displayName = "Button";

export { Button, buttonVariants };
