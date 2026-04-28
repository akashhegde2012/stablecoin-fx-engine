import { cn } from "@/lib/utils";

function Skeleton({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "animate-pulse rounded-lg bg-kaia-hover",
        className,
      )}
      {...props}
    />
  );
}

export { Skeleton };
