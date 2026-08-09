import type { Metadata } from "next";
import { requireBusiness } from "@/lib/auth/session";
import { SettingsForm } from "@/components/settings/settings-form";
import { updateAiSettingsAction } from "../actions";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { FaqEditor, type Faq } from "@/components/settings/faq-editor";
import { AI_TONES } from "@/lib/constants";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export const metadata: Metadata = { title: "AI Assistant settings" };

export default async function AiSettingsPage() {
  const { business } = await requireBusiness();
  const faqs = (business.aiFaqs as Faq[] | null) || [];

  return (
    <Card>
      <CardHeader>
        <CardTitle>AI Assistant</CardTitle>
        <CardDescription>
          This configures exactly what your AI assistant knows and how it behaves. It never
          invents information beyond what&apos;s here.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <SettingsForm action={updateAiSettingsAction}>
          <div className="space-y-1.5">
            <Label htmlFor="aiDescription">Business description</Label>
            <Textarea
              id="aiDescription"
              name="aiDescription"
              rows={3}
              defaultValue={business.aiDescription || ""}
              placeholder="A family-owned HVAC company serving the greater Austin area since 2010."
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="aiServices">Services</Label>
            <Textarea id="aiServices" name="aiServices" rows={3} defaultValue={business.aiServices || ""} />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="aiTypicalCustomer">Typical customer</Label>
            <Textarea
              id="aiTypicalCustomer"
              name="aiTypicalCustomer"
              rows={2}
              defaultValue={business.aiTypicalCustomer || ""}
              placeholder="Homeowners in the service area needing repair, maintenance, or new installs."
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor="aiTone">Tone</Label>
              <Select name="aiTone" defaultValue={business.aiTone}>
                <SelectTrigger id="aiTone">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {AI_TONES.map((t) => (
                    <SelectItem key={t.value} value={t.value}>
                      {t.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="aiBookingUrl">Booking URL</Label>
              <Input
                id="aiBookingUrl"
                name="aiBookingUrl"
                defaultValue={business.aiBookingUrl || ""}
                placeholder="https://yourbusiness.com/book"
              />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="aiEmergencyInstructions">Emergency instructions</Label>
            <Textarea
              id="aiEmergencyInstructions"
              name="aiEmergencyInstructions"
              rows={2}
              defaultValue={business.aiEmergencyInstructions || ""}
              placeholder="For gas leaks or active flooding, tell the customer to call 911 and then our emergency line at (555) 555-0100."
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="aiPricingInfo">Pricing information</Label>
            <Textarea
              id="aiPricingInfo"
              name="aiPricingInfo"
              rows={2}
              defaultValue={business.aiPricingInfo || ""}
              placeholder="Leave blank and the AI will say a team member will follow up with pricing."
            />
          </div>

          <FaqEditor initialFaqs={faqs} />

          <div className="space-y-1.5">
            <Label htmlFor="aiCustomInstructions">Custom instructions</Label>
            <Textarea
              id="aiCustomInstructions"
              name="aiCustomInstructions"
              rows={3}
              defaultValue={business.aiCustomInstructions || ""}
              placeholder="Any other guidance for how the AI should handle conversations."
            />
          </div>
        </SettingsForm>
      </CardContent>
    </Card>
  );
}
