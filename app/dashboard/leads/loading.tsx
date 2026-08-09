import { Card } from "@/components/ui/card";
import { TableSkeleton } from "@/components/ui/loading-state";
import { Skeleton } from "@/components/ui/skeleton";

export default function LeadsLoading() {
  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <Skeleton className="h-7 w-32" />
        <Skeleton className="h-9 w-28" />
      </div>
      <Card>
        <div className="border-b border-border p-4">
          <Skeleton className="h-8 w-full max-w-md" />
        </div>
        <TableSkeleton rows={8} cols={7} />
      </Card>
    </div>
  );
}
