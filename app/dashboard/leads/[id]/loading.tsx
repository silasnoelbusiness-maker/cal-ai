import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function LeadDetailLoading() {
  return (
    <div>
      <Skeleton className="mb-4 h-4 w-24" />
      <div className="mb-6 flex items-center justify-between">
        <Skeleton className="h-7 w-48" />
        <Skeleton className="h-9 w-40" />
      </div>
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-1">
          {Array.from({ length: 3 }).map((_, i) => (
            <Card key={i} className="p-6">
              <Skeleton className="h-5 w-32" />
              <div className="mt-4 space-y-3">
                {Array.from({ length: 3 }).map((__, j) => (
                  <Skeleton key={j} className="h-4 w-full" />
                ))}
              </div>
            </Card>
          ))}
        </div>
        <div className="lg:col-span-2">
          <Card className="h-[36rem] p-6">
            <Skeleton className="h-5 w-32" />
          </Card>
        </div>
      </div>
    </div>
  );
}
