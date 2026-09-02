"use client";

import { useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { formatCurrency, formatNumber } from "@/lib/utils";

export function RoiCalculator() {
  const [monthlyLeads, setMonthlyLeads] = useState(80);
  const [avgValue, setAvgValue] = useState(450);
  const [conversionRate, setConversionRate] = useState(25);
  const [recoveredPct, setRecoveredPct] = useState(15);

  const result = useMemo(() => {
    const leads = Math.max(monthlyLeads, 0);
    const value = Math.max(avgValue, 0);
    const conv = Math.min(Math.max(conversionRate, 0), 100);
    const recovered = Math.min(Math.max(recoveredPct, 0), 100);

    const currentlyConverted = leads * (conv / 100);
    const notConvertingToday = Math.max(leads - currentlyConverted, 0);
    const additionalConversions = notConvertingToday * (recovered / 100);
    const additionalRevenue = additionalConversions * value;

    return {
      currentlyConverted: Math.round(currentlyConverted),
      additionalConversions: Math.round(additionalConversions * 10) / 10,
      additionalRevenue: Math.round(additionalRevenue),
    };
  }, [monthlyLeads, avgValue, conversionRate, recoveredPct]);

  return (
    <Card className="mx-auto grid max-w-4xl gap-8 p-6 sm:p-8 lg:grid-cols-2">
      <div className="space-y-5">
        <Field
          label="Monthly leads"
          value={monthlyLeads}
          onChange={setMonthlyLeads}
          min={0}
          max={2000}
        />
        <Field
          label="Average customer value ($)"
          value={avgValue}
          onChange={setAvgValue}
          min={0}
          max={50000}
        />
        <SliderField
          label="Current conversion rate"
          value={conversionRate}
          onChange={setConversionRate}
          suffix="%"
        />
        <SliderField
          label="Leads Converana helps you recover"
          value={recoveredPct}
          onChange={setRecoveredPct}
          suffix="%"
        />
      </div>

      <div className="flex flex-col justify-center rounded-lg bg-muted-surface p-6">
        <p className="text-sm font-medium text-muted">Estimated additional monthly revenue</p>
        <p className="mt-2 text-4xl font-semibold tracking-tight text-foreground">
          {formatCurrency(result.additionalRevenue)}
        </p>
        <div className="mt-5 space-y-2 border-t border-border pt-4 text-sm text-muted">
          <div className="flex justify-between">
            <span>Leads converting today</span>
            <span className="font-medium text-foreground">
              {formatNumber(result.currentlyConverted)} / mo
            </span>
          </div>
          <div className="flex justify-between">
            <span>Additional conversions</span>
            <span className="font-medium text-foreground">
              {formatNumber(result.additionalConversions)} / mo
            </span>
          </div>
        </div>
        <p className="mt-5 text-xs leading-relaxed text-muted">
          This is an estimate based on the inputs above, not a guarantee. Calculation: additional
          revenue = (monthly leads − leads currently converting) × recovery rate × average
          customer value.
        </p>
      </div>
    </Card>
  );
}

function Field({
  label,
  value,
  onChange,
  min,
  max,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  min: number;
  max: number;
}) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      <Input
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        value={value}
        onChange={(e) => onChange(Number(e.target.value) || 0)}
      />
    </div>
  );
}

function SliderField({
  label,
  value,
  onChange,
  suffix,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  suffix: string;
}) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between">
        <Label>{label}</Label>
        <span className="text-sm font-medium text-foreground">
          {value}
          {suffix}
        </span>
      </div>
      <input
        type="range"
        min={0}
        max={100}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="range-slider"
        aria-label={label}
      />
    </div>
  );
}
