"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SettingsForm } from "@/components/settings/settings-form";
import { updateSmsSettingsAction } from "@/app/dashboard/settings/actions";

export function SmsNumberForm({ currentNumber }: { currentNumber: string | null }) {
  return (
    <SettingsForm action={updateSmsSettingsAction} submitLabel="Save number">
      <div className="space-y-1.5">
        <Label htmlFor="twilioPhoneNumber">Your Twilio phone number</Label>
        <Input
          id="twilioPhoneNumber"
          name="twilioPhoneNumber"
          defaultValue={currentNumber || ""}
          placeholder="+15125550100"
        />
        <p className="text-xs text-muted">
          E.164 format (starts with +, country code, no spaces). Leave blank to use the shared
          platform number for outbound only — a dedicated number is required for inbound replies
          to route back to this business.
        </p>
      </div>
    </SettingsForm>
  );
}
