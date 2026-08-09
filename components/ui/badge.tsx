import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

export const badgeVariants = cva(
  "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors w-fit",
  {
    variants: {
      variant: {
        default: "border-transparent bg-brand text-brand-foreground",
        secondary: "border-transparent bg-muted-surface text-foreground",
        outline: "border-border text-foreground",
        success: "border-transparent bg-success-surface text-success",
        warning: "border-transparent bg-warning-surface text-warning",
        danger: "border-transparent bg-danger-surface text-danger",
        hot: "border-transparent bg-hot-surface text-hot",
        warm: "border-transparent bg-warm-surface text-warm",
        cold: "border-transparent bg-cold-surface text-cold",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
);

export interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}
