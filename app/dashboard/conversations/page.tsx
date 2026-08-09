import type { Metadata } from "next";
import { MessageSquare } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { PageHeader } from "@/components/dashboard/page-header";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { ConversationList } from "@/components/conversations/conversation-list";
import { ConversationDetailHeader } from "@/components/conversations/conversation-detail-header";
import { ConversationPanel } from "@/components/conversations/conversation-panel";
import { cn } from "@/lib/utils";

export const metadata: Metadata = { title: "Conversations" };

export default async function ConversationsPage({ searchParams }: PageProps<"/dashboard/conversations">) {
  const { business } = await requireBusiness();
  const params = await searchParams;
  const requestedId = typeof params.id === "string" ? params.id : undefined;

  const conversations = await prisma.conversation.findMany({
    where: { businessId: business.id },
    orderBy: { updatedAt: "desc" },
    take: 50,
    include: { lead: true, messages: { orderBy: { createdAt: "desc" }, take: 1 } },
  });

  if (conversations.length === 0) {
    return (
      <div>
        <PageHeader title="Conversations" description="Every AI and manual conversation with your leads." />
        <EmptyState
          icon={MessageSquare}
          title="No conversations yet"
          description="Conversations start automatically when a new lead comes in. Add a lead to see one here."
        />
      </div>
    );
  }

  const selectedId = conversations.some((c) => c.id === requestedId) ? requestedId : conversations[0].id;

  const selected = await prisma.conversation.findFirst({
    where: { id: selectedId, businessId: business.id },
    include: { lead: true, messages: { orderBy: { createdAt: "asc" } } },
  });

  return (
    <div className="flex h-[calc(100vh-8.5rem)] flex-col md:h-[calc(100vh-7.5rem)]">
      <PageHeader title="Conversations" className="mb-4" />
      <Card className="flex flex-1 overflow-hidden p-0">
        <div
          className={cn(
            "w-full flex-col border-border md:flex md:w-80 md:border-r lg:w-96",
            requestedId ? "hidden" : "flex"
          )}
        >
          <ConversationList conversations={conversations} selectedId={selectedId} />
        </div>

        <div className={cn("min-w-0 flex-1 flex-col", requestedId ? "flex" : "hidden md:flex")}>
          {selected ? (
            <>
              <ConversationDetailHeader conversation={selected} lead={selected.lead} />
              <div className="flex min-h-0 flex-1 flex-col">
                <ConversationPanel conversationId={selected.id} initialMessages={selected.messages} />
              </div>
            </>
          ) : (
            <div className="flex flex-1 items-center justify-center text-sm text-muted">
              Select a conversation
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}
