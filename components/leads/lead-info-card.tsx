import { Mail, Phone, MapPin, Wrench, Tag, DollarSign, MessageSquareText } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { OptOutToggle } from "@/components/leads/opt-out-toggle";
import { formatCurrency, formatDate, unknownOr } from "@/lib/utils";
import type { Lead } from "@prisma/client";

const SOURCE_LABELS: Record<string, string> = {
  website: "Website",
  embed: "Embedded form",
  api: "API",
  manual: "Manual entry",
  google_ads: "Google Ads",
  facebook_ads: "Facebook Ads",
  referral: "Referral",
  phone: "Phone",
  other: "Other",
};

function Row({ icon: Icon, label, value }: { icon: typeof Mail; label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start gap-3 py-2.5">
      <Icon className="mt-0.5 h-4 w-4 shrink-0 text-muted" />
      <div className="min-w-0">
        <p className="text-xs text-muted">{label}</p>
        <p className="text-sm text-foreground">{value}</p>
      </div>
    </div>
  );
}

export function LeadInfoCard({ lead }: { lead: Lead }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Customer information</CardTitle>
      </CardHeader>
      <CardContent className="divide-y divide-border pt-0">
        <Row icon={Mail} label="Email" value={unknownOr(lead.email)} />
        <Row icon={Phone} label="Phone" value={unknownOr(lead.phone)} />
        <Row icon={Wrench} label="Service requested" value={unknownOr(lead.serviceRequested)} />
        <Row icon={Tag} label="Source" value={SOURCE_LABELS[lead.source] || lead.source} />
        <Row icon={MapPin} label="Location" value={unknownOr(lead.aiLocation)} />
        <Row
          icon={DollarSign}
          label="Estimated value"
          value={lead.estimatedValue ? formatCurrency(lead.estimatedValue.toString()) : "Unknown"}
        />
        {lead.message && <Row icon={MessageSquareText} label="Initial message" value={lead.message} />}
        <Row icon={Tag} label="Captured" value={formatDate(lead.createdAt)} />
        <div className="flex flex-wrap gap-1.5 pt-3">
          <Badge variant={lead.smsConsent ? "success" : "outline"}>
            SMS consent {lead.smsConsent ? "granted" : "not on file"}
          </Badge>
          <Badge variant={lead.emailConsent ? "success" : "outline"}>
            Email consent {lead.emailConsent ? "granted" : "not on file"}
          </Badge>
          <OptOutToggle leadId={lead.id} optedOut={lead.optedOut} />
        </div>
      </CardContent>
    </Card>
  );
}
