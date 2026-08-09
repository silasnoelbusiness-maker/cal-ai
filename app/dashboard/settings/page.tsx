import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { SettingsForm } from "@/components/settings/settings-form";
import { updateBusinessSettingsAction } from "./actions";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { INDUSTRIES, WEEKDAYS, DEFAULT_BUSINESS_HOURS } from "@/lib/constants";

export const metadata: Metadata = { title: "Business settings" };

const TIMEZONES = [
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Phoenix",
  "America/Anchorage",
  "Pacific/Honolulu",
];

export default async function BusinessSettingsPage() {
  const { business } = await requireBusiness();
  const hours = (business.businessHours as Record<string, string> | null) || DEFAULT_BUSINESS_HOURS;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Business</CardTitle>
        <CardDescription>Core details about your business.</CardDescription>
      </CardHeader>
      <CardContent>
        <SettingsForm action={updateBusinessSettingsAction}>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="name">Business name</Label>
              <Input id="name" name="name" defaultValue={business.name} required />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="industry">Industry</Label>
              <Select name="industry" defaultValue={business.industry || undefined}>
                <SelectTrigger id="industry">
                  <SelectValue placeholder="Select industry" />
                </SelectTrigger>
                <SelectContent>
                  {INDUSTRIES.map((i) => (
                    <SelectItem key={i} value={i}>
                      {i}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="website">Website</Label>
              <Input id="website" name="website" defaultValue={business.website || ""} placeholder="https://" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="phone">Phone</Label>
              <Input id="phone" name="phone" defaultValue={business.phone || ""} />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="email">Business email</Label>
              <Input id="email" name="email" type="email" defaultValue={business.email || ""} />
              <p className="text-xs text-muted">Used for notifications when a lead needs attention.</p>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="timezone">Timezone</Label>
              <Select name="timezone" defaultValue={business.timezone}>
                <SelectTrigger id="timezone">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {TIMEZONES.map((tz) => (
                    <SelectItem key={tz} value={tz}>
                      {tz}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="serviceArea">Service area</Label>
            <Input id="serviceArea" name="serviceArea" defaultValue={business.serviceArea || ""} />
          </div>

          <div>
            <Label>Business hours</Label>
            <div className="mt-2 space-y-2">
              {WEEKDAYS.map((day) => (
                <div key={day.key} className="flex items-center gap-3">
                  <span className="w-24 shrink-0 text-sm text-muted">{day.label}</span>
                  <Input name={`hours_${day.key}`} defaultValue={hours[day.key] || "Closed"} />
                </div>
              ))}
            </div>
          </div>

          <div className="flex items-center justify-between rounded-md border border-border p-4">
            <div>
              <Label htmlFor="aiEnabled">AI assistant enabled</Label>
              <p className="mt-0.5 text-xs text-muted">
                Turn off to stop AI from responding to or qualifying leads business-wide.
              </p>
            </div>
            <Switch id="aiEnabled" name="aiEnabled" defaultChecked={business.aiEnabled} />
          </div>
        </SettingsForm>
      </CardContent>
    </Card>
  );
}
