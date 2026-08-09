import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { SettingsForm } from "@/components/settings/settings-form";
import { updateNotificationSettingsAction } from "../actions";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { isResendConfigured, isTwilioConfigured } from "@/lib/auth/config";
import { ConfigNotice } from "@/components/ui/config-notice";

export const metadata: Metadata = { title: "Notification settings" };

function ToggleRow({
  name,
  label,
  description,
  defaultChecked,
  disabled,
}: {
  name: string;
  label: string;
  description: string;
  defaultChecked: boolean;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-start justify-between gap-4 py-3">
      <div>
        <Label htmlFor={name}>{label}</Label>
        <p className="mt-0.5 text-xs text-muted">{description}</p>
      </div>
      <Switch id={name} name={name} defaultChecked={defaultChecked} disabled={disabled} />
    </div>
  );
}

export default async function NotificationSettingsPage() {
  const { business } = await requireBusiness();
  const settings = await prisma.notificationSettings.upsert({
    where: { businessId: business.id },
    create: { businessId: business.id },
    update: {},
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Notifications</CardTitle>
        <CardDescription>Choose when and how LeadLoop alerts you.</CardDescription>
      </CardHeader>
      <CardContent>
        {(!isResendConfigured || !isTwilioConfigured) && (
          <ConfigNotice
            className="mb-5"
            title="Some delivery channels aren't configured"
            description={[
              !isResendConfigured && "Email notifications need RESEND_API_KEY.",
              !isTwilioConfigured && "SMS notifications need Twilio credentials.",
            ]
              .filter(Boolean)
              .join(" ")}
          />
        )}
        <SettingsForm action={updateNotificationSettingsAction}>
          <div className="grid grid-cols-2 gap-4 rounded-md border border-border p-4">
            <div className="flex items-center justify-between">
              <Label htmlFor="emailEnabled">Email</Label>
              <Switch id="emailEnabled" name="emailEnabled" defaultChecked={settings.emailEnabled} />
            </div>
            <div className="flex items-center justify-between">
              <Label htmlFor="smsEnabled">SMS</Label>
              <Switch id="smsEnabled" name="smsEnabled" defaultChecked={settings.smsEnabled} />
            </div>
          </div>

          <div className="divide-y divide-border">
            <ToggleRow
              name="onNewLead"
              label="New lead"
              description="A new lead comes in from any source."
              defaultChecked={settings.onNewLead}
            />
            <ToggleRow
              name="onHotLead"
              label="Hot lead"
              description="AI identifies a lead as high intent."
              defaultChecked={settings.onHotLead}
            />
            <ToggleRow
              name="onQualifiedLead"
              label="Qualified lead"
              description="AI finishes qualifying a lead."
              defaultChecked={settings.onQualifiedLead}
            />
            <ToggleRow
              name="onAppointmentBooked"
              label="Appointment booked"
              description="A new appointment is scheduled."
              defaultChecked={settings.onAppointmentBooked}
            />
            <ToggleRow
              name="onNeedsHuman"
              label="Needs human"
              description="AI flags a conversation that needs your attention."
              defaultChecked={settings.onNeedsHuman}
            />
          </div>
        </SettingsForm>
      </CardContent>
    </Card>
  );
}
