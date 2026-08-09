import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function ConversationsLoading() {
  return (
    <div className="flex h-[calc(100vh-8.5rem)] flex-col md:h-[calc(100vh-7.5rem)]">
      <Skeleton className="mb-4 h-7 w-40" />
      <Card className="flex flex-1 overflow-hidden p-0">
        <div className="hidden w-80 flex-col divide-y divide-border border-r border-border md:flex lg:w-96">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="flex gap-3 p-4">
              <Skeleton className="h-9 w-9 shrink-0 rounded-full" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-3.5 w-24" />
                <Skeleton className="h-3 w-full" />
              </div>
            </div>
          ))}
        </div>
        <div className="flex-1" />
      </Card>
    </div>
  );
}
