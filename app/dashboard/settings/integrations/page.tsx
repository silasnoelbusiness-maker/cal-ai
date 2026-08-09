import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { CopyButton } from "@/components/ui/copy-button";
import { SmsNumberForm } from "@/components/settings/sms-number-form";
import { isTwilioConfigured } from "@/lib/auth/config";
import { ConfigNotice } from "@/components/ui/config-notice";
import { Label } from "@/components/ui/label";
import Link from "next/link";

export const metadata: Metadata = { title: "Integrations" };

export default async function IntegrationsPage() {
  const { business } = await requireBusiness();
  const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";
  const embedUrl = `${appUrl}/embed/${business.id}`;
  const iframeSnippet = `<iframe
  src="${embedUrl}"
  style="width: 100%; max-width: 480px; height: 640px; border: none;"
  title="Request service"
></iframe>`;

  const smsWebhookUrl = `${appUrl}/api/webhooks/twilio/sms`;

  const curlSnippet = `curl -X POST ${appUrl}/api/leads \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "firstName": "John",
    "lastName": "Smith",
    "email": "john@example.com",
    "phone": "+15555555555",
    "service": "Roof repair",
    "message": "My roof is leaking",
    "source": "website"
  }'`;

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Embeddable lead form</CardTitle>
          <CardDescription>
            Paste this snippet into your website&apos;s HTML — no coding required. It shows a
            simple form that sends new leads straight into LeadLoop.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="relative">
            <pre className="overflow-x-auto scrollbar-thin rounded-md border border-border bg-muted-surface p-4 text-xs text-foreground">
              {iframeSnippet}
            </pre>
            <div className="mt-2 flex justify-end">
              <CopyButton value={iframeSnippet} label="Copy Code" />
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>SMS (Twilio)</CardTitle>
          <CardDescription>
            Connect a Twilio number so customers can text this business directly — replies are
            picked up automatically, added to the conversation, and answered by AI when enabled.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {!isTwilioConfigured && (
            <ConfigNotice
              title="Twilio isn't configured on this deployment"
              description="Set TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN before customers can text in — inbound messages are rejected until then."
            />
          )}
          <SmsNumberForm currentNumber={business.twilioPhoneNumber} />
          <div className="border-t border-border pt-4">
            <Label>Webhook URL</Label>
            <p className="mb-2 text-xs text-muted">
              In the Twilio console, open this number → Messaging → &quot;A message comes in&quot;
              → set to Webhook, HTTP POST, and paste this URL.
            </p>
            <div className="flex items-center gap-2">
              <pre className="flex-1 overflow-x-auto scrollbar-thin rounded-md border border-border bg-muted-surface p-3 text-xs text-foreground">
                {smsWebhookUrl}
              </pre>
              <CopyButton value={smsWebhookUrl} label="Copy" />
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Lead capture API</CardTitle>
          <CardDescription>
            Send leads from any form, CRM, or ad platform using an{" "}
            <Link href="/dashboard/settings/api-keys" className="text-brand hover:underline">
              API key
            </Link>
            .
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="relative">
            <pre className="overflow-x-auto scrollbar-thin rounded-md border border-border bg-muted-surface p-4 text-xs text-foreground">
              {curlSnippet}
            </pre>
            <div className="mt-2 flex justify-end">
              <CopyButton value={curlSnippet} label="Copy Code" />
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
