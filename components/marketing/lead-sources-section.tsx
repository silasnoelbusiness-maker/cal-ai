import { Code2, FileSpreadsheet, LayoutTemplate, Mail, MessageSquare, Phone, Plug } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { CHANNELS, LEAD_SOURCES } from "@/lib/marketing/product-facts";

/**
 * "Bring Every Lead Into One Place".
 *
 * Lists only what is actually implemented — see lib/marketing/product-facts.ts,
 * where each entry names the file behind it. The `kind` and `status` badges
 * exist so a visitor can tell a built-in feature from one that needs their own
 * Twilio account, rather than discovering the difference after signing up.
 */

const SOURCE_ICONS: Record<string, typeof Plug> = {
  "Embeddable lead form": LayoutTemplate,
  "CSV import": FileSpreadsheet,
  "Lead capture API": Code2,
  "Inbound SMS": MessageSquare,
  "Add by hand": Plug,
};

const CHANNEL_ICONS: Record<string, typeof Plug> = {
  Email: Mail,
  SMS: MessageSquare,
  "Web conversation": LayoutTemplate,
};

const KIND_LABEL: Record<string, { text: string; variant: "success" | "warning" | "secondary" }> = {
  native: { text: "Built in", variant: "success" },
  byo: { text: "Needs your Twilio account", variant: "warning" },
  indirect: { text: "Via API or CSV", variant: "secondary" },
};

export function LeadSourcesSection() {
  return (
    <section className="scroll-mt-20 border-t border-border bg-background py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            Bring every lead into one place
          </h2>
          <p className="mt-4 text-lg text-muted">
            However a lead reaches you, it lands in the same inbox and gets the same follow-up.
          </p>
        </div>

        <h3 className="mt-14 text-sm font-semibold uppercase tracking-wide text-muted">
          Where leads come from
        </h3>
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {LEAD_SOURCES.map((source) => {
            const Icon = SOURCE_ICONS[source.title] ?? Plug;
            const kind = KIND_LABEL[source.kind];
            return (
              <Card key={source.title} className="flex min-w-0 flex-col p-5">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-brand/10 text-brand">
                    <Icon className="h-4 w-4" aria-hidden />
                  </div>
                  <Badge variant={kind.variant} className="shrink-0 text-[10px]">
                    {kind.text}
                  </Badge>
                </div>
                <h4 className="mt-3 text-sm font-semibold text-foreground">{source.title}</h4>
                <p className="mt-1.5 text-sm text-muted">{source.body}</p>
              </Card>
            );
          })}
        </div>

        <h3 className="mt-12 text-sm font-semibold uppercase tracking-wide text-muted">
          How Converana talks to them
        </h3>
        <div className="mt-4 grid gap-4 sm:grid-cols-3">
          {CHANNELS.map((channel) => {
            const Icon = CHANNEL_ICONS[channel.title] ?? Plug;
            return (
              <Card key={channel.title} className="flex min-w-0 flex-col p-5">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-brand/10 text-brand">
                    <Icon className="h-4 w-4" aria-hidden />
                  </div>
                  {channel.status === "byo" && (
                    <Badge variant="warning" className="shrink-0 text-[10px]">
                      Needs your Twilio account
                    </Badge>
                  )}
                </div>
                <h4 className="mt-3 text-sm font-semibold text-foreground">{channel.title}</h4>
                <p className="mt-1.5 text-sm text-muted">{channel.body}</p>
              </Card>
            );
          })}
        </div>

        {/*
          Stated outright rather than left for a visitor to discover. Voice is
          in the ConversationChannel enum but has no implementation, and there
          is no native Facebook/Google connector — only the generic API.
        */}
        <div className="mt-8 flex items-start gap-3 rounded-lg border border-border bg-muted-surface/40 px-4 py-3">
          <Phone className="mt-0.5 h-4 w-4 shrink-0 text-muted" aria-hidden />
          <p className="text-sm text-muted">
            <span className="font-medium text-foreground">Not available yet:</span> Converana
            doesn&apos;t make or answer phone calls, and there&apos;s no one-click Facebook or
            Google Ads connector today. Leads from ad platforms can still come in through the lead
            capture API or a CSV export.
          </p>
        </div>
      </div>
    </section>
  );
}
