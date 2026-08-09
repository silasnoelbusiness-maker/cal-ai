import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";

export const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-brand text-brand-foreground shadow-sm hover:bg-brand-hover",
        destructive: "bg-danger text-white shadow-sm hover:bg-danger/90",
        outline:
          "border border-border bg-surface text-foreground shadow-sm hover:bg-muted-surface",
        secondary: "bg-muted-surface text-foreground hover:bg-border/60",
        ghost: "text-foreground hover:bg-muted-surface",
        link: "text-brand underline-offset-4 hover:underline",
      },
      size: {
        default: "h-9 px-4 py-2",
        sm: "h-8 rounded-md px-3 text-xs",
        lg: "h-11 rounded-md px-6 text-base",
        icon: "h-9 w-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
  loading?: boolean;
}

export function Button({
  className,
  variant,
  size,
  asChild = false,
  loading = false,
  disabled,
  children,
  ref,
  ...props
}: ButtonProps & { ref?: React.Ref<HTMLButtonElement> }) {
  if (asChild) {
    return (
      <Slot
        ref={ref}
        className={cn(buttonVariants({ variant, size, className }))}
        {...props}
      >
        {children}
      </Slot>
    );
  }

  return (
    <button
      ref={ref}
      className={cn(buttonVariants({ variant, size, className }))}
      disabled={disabled || loading}
      {...props}
    >
      {loading && <Loader2 className="animate-spin" />}
      {children}
    </button>
  );
}
