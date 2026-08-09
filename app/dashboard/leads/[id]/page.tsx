import { notFound } from "next/navigation";
import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { LeadHeader } from "@/components/leads/lead-header";
import { LeadInfoCard } from "@/components/leads/lead-info-card";
import { LeadAiSummaryCard } from "@/components/leads/lead-ai-summary-card";
import { LeadTimeline } from "@/components/leads/lead-timeline";
import { LeadAppointmentsCard } from "@/components/leads/lead-appointments-card";
import { ConversationPanel } from "@/components/conversations/conversation-panel";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";

export async function generateMetadata({ params }: PageProps<"/dashboard/leads/[id]">): Promise<Metadata> {
  const { id } = await params;
  const lead = await prisma.lead.findUnique({ where: { id } });
  return { title: lead ? `${lead.firstName} ${lead.lastName || ""}`.trim() : "Lead" };
}

export default async function LeadDetailPage({ params }: PageProps<"/dashboard/leads/[id]">) {
  const { business } = await requireBusiness();
  const { id } = await params;

  const lead = await prisma.lead.findFirst({ where: { id, businessId: business.id } });
  if (!lead) notFound();

  const [events, appointments, conversation] = await Promise.all([
    prisma.leadEvent.findMany({ where: { leadId: lead.id }, orderBy: { createdAt: "desc" } }),
    prisma.appointment.findMany({ where: { leadId: lead.id }, orderBy: { scheduledAt: "desc" } }),
    prisma.conversation.findFirst({
      where: { leadId: lead.id },
      orderBy: { createdAt: "asc" },
      include: { messages: { orderBy: { createdAt: "asc" } } },
    }),
  ]);

  return (
    <div>
      <LeadHeader lead={lead} />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-1">
          <LeadInfoCard lead={lead} />
          <LeadAiSummaryCard lead={lead} />
          <LeadAppointmentsCard leadId={lead.id} appointments={appointments} />
          <LeadTimeline events={events} />
        </div>

        <div className="lg:col-span-2">
          <Card className="flex h-[36rem] flex-col overflow-hidden">
            <CardHeader className="border-b border-border">
              <CardTitle>Conversation</CardTitle>
            </CardHeader>
            {conversation ? (
              <ConversationPanel conversationId={conversation.id} initialMessages={conversation.messages} />
            ) : (
              <div className="flex flex-1 items-center justify-center text-sm text-muted">
                No conversation yet.
              </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
