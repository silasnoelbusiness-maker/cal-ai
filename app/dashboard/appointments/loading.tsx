import { Skeleton } from "@/components/ui/skeleton";
import { Card } from "@/components/ui/card";

export default function AppointmentsLoading() {
  return (
    <div>
      <Skeleton className="mb-6 h-7 w-40" />
      <div className="mb-4 flex gap-2">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-8 w-20 rounded-full" />
        ))}
      </div>
      <div className="space-y-3">
        {Array.from({ length: 4 }).map((_, i) => (
          <Card key={i} className="p-4">
            <Skeleton className="h-10 w-full" />
          </Card>
        ))}
      </div>
    </div>
  );
}
