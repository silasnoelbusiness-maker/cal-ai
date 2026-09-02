"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowRight, PlayCircle, Video } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ProductPreview } from "./product-preview";

/**
 * "Watch 60-Second Demo".
 *
 * ─────────────────────────────────────────────────────────────────────────
 *  PLACEHOLDER — NO DEMO VIDEO EXISTS YET
 *
 *  There is no video file anywhere in this project (public/ contains only
 *  icon.svg). Rather than claim a recording exists, this modal shows the
 *  real product interface and says plainly that the walkthrough is coming.
 *
 *  TO ACTIVATE: drop the recording somewhere it can be served, then set
 *  DEMO_VIDEO_URL below. The modal switches to the player automatically and
 *  the placeholder copy disappears — no other change needed.
 * ─────────────────────────────────────────────────────────────────────────
 */
const DEMO_VIDEO_URL: string | null = null;

export function DemoModalTrigger({
  variant = "outline",
  size = "lg",
  className,
  children,
}: {
  variant?: ButtonProps["variant"];
  size?: ButtonProps["size"];
  className?: string;
  children?: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button variant={variant} size={size} className={className} onClick={() => setOpen(true)}>
        <PlayCircle className="h-4 w-4" aria-hidden />
        {children ?? "Watch 60-Second Demo"}
      </Button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle>
              {DEMO_VIDEO_URL ? "Converana in 60 seconds" : "A look at Converana"}
            </DialogTitle>
            <DialogDescription>
              {DEMO_VIDEO_URL
                ? "How a missed lead becomes a booked job."
                : "The recorded walkthrough is on its way. In the meantime, this is the actual Converana interface — not a mock-up of a different product."}
            </DialogDescription>
          </DialogHeader>

          {DEMO_VIDEO_URL ? (
            <video
              className="w-full rounded-lg border border-border"
              controls
              autoPlay
              playsInline
              src={DEMO_VIDEO_URL}
            >
              Your browser can&apos;t play this video.
            </video>
          ) : (
            <div className="space-y-4">
              <div className="rounded-lg bg-muted-surface/50 p-3 sm:p-4">
                <ProductPreview />
              </div>
              <p className="flex items-start gap-2 text-xs text-muted">
                <Video className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />
                <span>
                  Illustrative data. The figures shown demonstrate what Converana tracks — they
                  aren&apos;t results from a customer account.
                </span>
              </p>
              <div className="flex flex-col gap-2 sm:flex-row">
                <Button asChild className="sm:flex-1">
                  <Link href="/signup">
                    Start Free
                    <ArrowRight className="h-4 w-4" aria-hidden />
                  </Link>
                </Button>
                <Button variant="outline" asChild className="sm:flex-1">
                  <Link href="/#how-it-works" onClick={() => setOpen(false)}>
                    Read how it works
                  </Link>
                </Button>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
