import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function AnalyticsLoading() {
  return (
    <div>
      <Skeleton className="mb-6 h-7 w-40" />
      <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        {Array.from({ length: 9 }).map((_, i) => (
          <Card key={i} className="p-5">
            <Skeleton className="h-4 w-20" />
            <Skeleton className="mt-3 h-6 w-14" />
          </Card>
        ))}
      </div>
      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        {Array.from({ length: 2 }).map((_, i) => (
          <Card key={i} className="p-6">
            <Skeleton className="h-5 w-32" />
            <Skeleton className="mt-4 h-56 w-full" />
          </Card>
        ))}
      </div>
    </div>
  );
}
