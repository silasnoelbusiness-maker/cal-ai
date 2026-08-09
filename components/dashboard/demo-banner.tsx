import { FlaskConical } from "lucide-react";
import { hasDemoData } from "@/lib/demo";
import { removeDemoDataAction } from "@/app/dashboard/demo-actions";
import { Button } from "@/components/ui/button";

export async function DemoBanner({ businessId }: { businessId: string }) {
  const isDemo = await hasDemoData(businessId);
  if (!isDemo) return null;

  return (
    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-warning/30 bg-warning-surface px-4 py-2 text-sm sm:px-6">
      <span className="flex items-center gap-2 text-foreground">
        <FlaskConical className="h-4 w-4 text-warning" />
        You&apos;re viewing sample data so you can explore LeadLoop.
      </span>
      <form action={removeDemoDataAction}>
        <Button type="submit" size="sm" variant="outline">
          Remove Demo Data
        </Button>
      </form>
    </div>
  );
}
