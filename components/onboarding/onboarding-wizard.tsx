"use client";

import { useActionState, useState } from "react";
import { useRouter } from "next/navigation";
import { Check, ChevronLeft, ChevronRight, Code2, Sparkles } from "lucide-react";
import { completeOnboardingAction, type OnboardingFormState } from "@/app/onboarding/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { INDUSTRIES, AI_TONES, WEEKDAYS, DEFAULT_BUSINESS_HOURS } from "@/lib/constants";
import { cn } from "@/lib/utils";
import type { Business } from "@prisma/client";

const STEP_LABELS = [
  "Business",
  "Industry",
  "Services",
  "Service area",
  "Hours",
  "AI tone",
  "Lead source",
  "Finish",
];

const initialState: OnboardingFormState = {};

export function OnboardingWizard({ business }: { business: Business | null }) {
  const [step, setStep] = useState(0);
  const [industry, setIndustry] = useState(business?.industry || "");
  const [tone, setTone] = useState(business?.aiTone || "professional");
  const [name, setName] = useState(business?.name || "");
  const [loadDemo, setLoadDemo] = useState(true);
  const [state, formAction, pending] = useActionState(completeOnboardingAction, initialState);
  const router = useRouter();

  const lastStep = STEP_LABELS.length - 1;

  function goNext() {
    if (step === 0 && name.trim().length < 2) return;
    if (step === 1 && !industry) return;
    setStep((s) => Math.min(s + 1, lastStep));
  }

  function goBack() {
    setStep((s) => Math.max(s - 1, 0));
  }

  const hours = (business?.businessHours as Record<string, string> | null) || DEFAULT_BUSINESS_HOURS;

  return (
    <div className="mx-auto w-full max-w-xl">
      <div className="mb-8">
        <div className="mb-2 flex items-center justify-between text-xs font-medium text-muted">
          <span>
            Step {step + 1} of {STEP_LABELS.length}
          </span>
          <span>{STEP_LABELS[step]}</span>
        </div>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted-surface">
          <div
            className="h-full rounded-full bg-brand transition-all"
            style={{ width: `${((step + 1) / STEP_LABELS.length) * 100}%` }}
          />
        </div>
      </div>

      <form action={formAction} className="rounded-xl border border-border bg-surface p-6 sm:p-8">
        <input type="hidden" name="loadDemo" value={loadDemo ? "on" : "off"} />

        <div className={cn(step !== 0 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">What&apos;s your business called?</h2>
          <p className="mt-1 text-sm text-muted">This is how LeadLoop will refer to your business.</p>
          <div className="mt-6 space-y-1.5">
            <Label htmlFor="name">Business name</Label>
            <Input
              id="name"
              name="name"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="PeakFlow HVAC"
              autoFocus
            />
          </div>
        </div>

        <div className={cn(step !== 1 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">What industry are you in?</h2>
          <p className="mt-1 text-sm text-muted">This helps LeadLoop tailor AI qualification.</p>
          <input type="hidden" name="industry" value={industry} />
          <div className="mt-6 grid grid-cols-2 gap-2">
            {INDUSTRIES.map((ind) => (
              <button
                type="button"
                key={ind}
                onClick={() => setIndustry(ind)}
                className={cn(
                  "rounded-md border px-3 py-2.5 text-left text-sm font-medium transition-colors",
                  industry === ind
                    ? "border-brand bg-brand/5 text-brand"
                    : "border-border text-foreground hover:bg-muted-surface"
                )}
              >
                {ind}
              </button>
            ))}
          </div>
        </div>

        <div className={cn(step !== 2 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">What services do you offer?</h2>
          <p className="mt-1 text-sm text-muted">
            Briefly list your services — the AI assistant uses this to answer questions accurately.
          </p>
          <div className="mt-6 space-y-1.5">
            <Label htmlFor="services">Services</Label>
            <Textarea
              id="services"
              name="services"
              rows={4}
              defaultValue={business?.aiServices || ""}
              placeholder="AC repair, AC installation, furnace repair, duct cleaning, routine maintenance plans"
            />
          </div>
        </div>

        <div className={cn(step !== 3 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">Where do you provide service?</h2>
          <p className="mt-1 text-sm text-muted">Cities, metro area, or a mile radius all work.</p>
          <div className="mt-6 space-y-1.5">
            <Label htmlFor="serviceArea">Service area</Label>
            <Input
              id="serviceArea"
              name="serviceArea"
              defaultValue={business?.serviceArea || ""}
              placeholder="Austin, TX and surrounding areas (25 mi)"
            />
          </div>
        </div>

        <div className={cn(step !== 4 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">What are your business hours?</h2>
          <p className="mt-1 text-sm text-muted">The AI assistant uses this — it won&apos;t promise availability outside these hours.</p>
          <div className="mt-6 space-y-2">
            {WEEKDAYS.map((day) => (
              <div key={day.key} className="flex items-center gap-3">
                <Label className="w-24 shrink-0 text-sm text-muted">{day.label}</Label>
                <Input name={`hours_${day.key}`} defaultValue={hours[day.key] || "Closed"} />
              </div>
            ))}
          </div>
        </div>

        <div className={cn(step !== 5 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">Choose your AI assistant&apos;s tone</h2>
          <p className="mt-1 text-sm text-muted">You can change this anytime in AI settings.</p>
          <input type="hidden" name="aiTone" value={tone} />
          <div className="mt-6 space-y-2">
            {AI_TONES.map((t) => (
              <button
                type="button"
                key={t.value}
                onClick={() => setTone(t.value)}
                className={cn(
                  "flex w-full items-center justify-between rounded-md border px-4 py-3 text-left transition-colors",
                  tone === t.value ? "border-brand bg-brand/5" : "border-border hover:bg-muted-surface"
                )}
              >
                <span>
                  <span className="block text-sm font-medium text-foreground">{t.label}</span>
                  <span className="block text-xs text-muted">{t.description}</span>
                </span>
                {tone === t.value && <Check className="h-4 w-4 shrink-0 text-brand" />}
              </button>
            ))}
          </div>
        </div>

        <div className={cn(step !== 6 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">Connect a lead source</h2>
          <p className="mt-1 text-sm text-muted">
            You can embed a lead form on your website or send leads via API. Finish setup now — you&apos;ll find your embed code and API keys anytime under Settings → Integrations.
          </p>
          <div className="mt-6 space-y-3">
            <div className="flex items-start gap-3 rounded-md border border-border p-4">
              <Code2 className="mt-0.5 h-5 w-5 shrink-0 text-brand" />
              <div>
                <p className="text-sm font-medium text-foreground">Embeddable lead form</p>
                <p className="text-xs text-muted">
                  Copy a snippet onto your website to start capturing leads immediately.
                </p>
              </div>
            </div>
            <div className="flex items-start gap-3 rounded-md border border-border p-4">
              <Sparkles className="mt-0.5 h-5 w-5 shrink-0 text-brand" />
              <div>
                <p className="text-sm font-medium text-foreground">Lead capture API</p>
                <p className="text-xs text-muted">
                  Send leads from any form, CRM, or ad platform using your LeadLoop API key.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className={cn(step !== 7 && "hidden")}>
          <h2 className="text-lg font-semibold text-foreground">You&apos;re all set.</h2>
          <p className="mt-1 text-sm text-muted">Your LeadLoop workspace is ready.</p>
          <div className="mt-6 flex items-start justify-between gap-4 rounded-md border border-border p-4">
            <div>
              <p className="text-sm font-medium text-foreground">Load sample data</p>
              <p className="text-xs text-muted">
                Explore LeadLoop with a few realistic sample leads, conversations, and an
                appointment. Clearly labeled as demo data — remove anytime from Settings.
              </p>
            </div>
            <Switch checked={loadDemo} onCheckedChange={setLoadDemo} />
          </div>
          {state.error && (
            <p role="alert" className="mt-4 text-sm text-danger">
              {state.error}
            </p>
          )}
        </div>

        <div className="mt-8 flex items-center justify-between border-t border-border pt-6">
          <Button
            type="button"
            variant="ghost"
            onClick={step === 0 ? () => router.push("/dashboard") : goBack}
          >
            {step === 0 ? "Skip for now" : (
              <>
                <ChevronLeft className="h-4 w-4" /> Back
              </>
            )}
          </Button>

          {step < lastStep ? (
            <Button type="button" onClick={goNext}>
              Continue
              <ChevronRight className="h-4 w-4" />
            </Button>
          ) : (
            <Button type="submit" loading={pending}>
              Enter Dashboard
            </Button>
          )}
        </div>
      </form>
    </div>
  );
}
