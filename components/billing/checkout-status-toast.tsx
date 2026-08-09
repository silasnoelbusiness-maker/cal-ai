"use client";

import { useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { toast } from "sonner";

export function CheckoutStatusToast() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const status = searchParams.get("checkout");

  useEffect(() => {
    if (status === "success") {
      toast.success("Subscription updated. It may take a few seconds to reflect below.");
      router.replace("/dashboard/billing");
    } else if (status === "cancelled") {
      toast("Checkout cancelled.");
      router.replace("/dashboard/billing");
    }
  }, [status, router]);

  return null;
}
