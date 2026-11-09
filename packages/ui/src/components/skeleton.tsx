import { cn } from "../lib/utils";

export function Skeleton({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "animate-pulse rounded-[var(--radius)] bg-[hsl(var(--muted))] dark:bg-[hsl(var(--secondary))]",
        className,
      )}
      {...props}
    />
  );
}