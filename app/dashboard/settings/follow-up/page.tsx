import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { SettingsForm } from "@/components/settings/settings-form";
import { updateFollowUpSettingsAction } from "./actions";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export const metadata: Metadata = { title: "Follow-up settings" };

function ToggleRow({
  name,
  label,
  description,
  defaultChecked,
}: {
  name: string;
  label: string;
  description: string;
  defaultChecked: boolean;
}) {
  return (
    <div className="flex items-start justify-between gap-4 py-3">
      <div>
        <Label htmlFor={name}>{label}</Label>
        <p className="mt-0.5 text-xs text-muted">{description}</p>
      </div>
      <Switch id={name} name={name} defaultChecked={defaultChecked} />
    </div>
  );
}

export default async function FollowUpSettingsPage() {
  const { business } = await requireBusiness();
  const settings = await prisma.followUpSettings.upsert({
    where: { businessId: business.id },
    create: { businessId: business.id },
    update: {},
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Follow-up automation</CardTitle>
        <CardDescription>
          Control how and when LeadLoop automatically follows up with leads who go quiet.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <SettingsForm action={updateFollowUpSettingsAction}>
          <div className="divide-y divide-border">
            <ToggleRow
              name="enabled"
              label="Enable follow-up automation"
              description="Turn off to stop all automated follow-ups business-wide."
              defaultChecked={settings.enabled}
            />
            <ToggleRow
              name="immediateResponse"
              label="Immediate AI response"
              description="Send an AI reply the moment a new lead comes in."
              defaultChecked={settings.immediateResponse}
            />
            <ToggleRow
              name="delay30MinEnabled"
              label="30-minute follow-up"
              description="Quick check-in if there's been no reply."
              defaultChecked={settings.delay30MinEnabled}
            />
            <ToggleRow
              name="delay24HourEnabled"
              label="24-hour follow-up"
              description="Second follow-up about a day after the lead came in."
              defaultChecked={settings.delay24HourEnabled}
            />
            <ToggleRow
              name="delay3DayEnabled"
              label="3-day follow-up"
              description="Final, low-pressure follow-up a few days later."
              defaultChecked={settings.delay3DayEnabled}
            />
          </div>

          <div className="grid grid-cols-2 gap-4 pt-2">
            <div className="space-y-1.5">
              <Label htmlFor="maxFollowUps">Maximum follow-ups</Label>
              <Input
                id="maxFollowUps"
                name="maxFollowUps"
                type="number"
                min={0}
                max={10}
                defaultValue={settings.maxFollowUps}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="defaultChannel">Default channel</Label>
              <Select name="defaultChannel" defaultValue={settings.defaultChannel}>
                <SelectTrigger id="defaultChannel">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="EMAIL">Email</SelectItem>
                  <SelectItem value="SMS">SMS</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
        </SettingsForm>
      </CardContent>
    </Card>
  );
}
