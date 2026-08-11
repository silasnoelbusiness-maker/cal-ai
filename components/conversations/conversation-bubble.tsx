import type { MessageSender } from "@prisma/client";
import { Sparkles } from "lucide-react";
import { cn, formatDateTime } from "@/lib/utils";

export function ConversationBubble({
  sender,
  content,
  aiGenerated,
  createdAt,
}: {
  sender: MessageSender;
  content: string;
  aiGenerated: boolean;
  createdAt: Date | string;
}) {
  if (sender === "SYSTEM") {
    return (
      <div className="flex justify-center py-1">
        <span className="rounded-full bg-muted-surface px-3 py-1 text-xs text-muted">
          {content}
        </span>
      </div>
    );
  }

  const isCustomer = sender === "CUSTOMER";
  const senderLabel = sender === "AI" ? "Converana AI" : sender === "BUSINESS" ? "You" : "Customer";

  return (
    <div className={cn("flex flex-col gap-1", isCustomer ? "items-start" : "items-end")}>
      <div className="flex items-center gap-2 px-1 text-xs text-muted">
        <span className="font-medium">{senderLabel}</span>
        {aiGenerated && (
          <span className="inline-flex items-center gap-0.5 rounded-full bg-brand/10 px-1.5 py-0.5 text-[10px] font-medium text-brand">
            <Sparkles className="h-2.5 w-2.5" />
            AI Generated
          </span>
        )}
        <span>{formatDateTime(createdAt)}</span>
      </div>
      <div
        className={cn(
          "max-w-[85%] rounded-lg px-3.5 py-2.5 text-sm leading-relaxed whitespace-pre-wrap break-words sm:max-w-[70%]",
          isCustomer && "bg-muted-surface text-foreground rounded-tl-sm",
          sender === "AI" && "bg-brand/10 text-foreground rounded-tr-sm",
          sender === "BUSINESS" && "bg-brand text-brand-foreground rounded-tr-sm"
        )}
      >
        {content}
      </div>
    </div>
  );
}
