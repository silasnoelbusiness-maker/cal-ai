"use client";

import { Flame, Sun, Snowflake, Calendar } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/ui/avatar";
import { MetricCard } from "@/components/ui/metric-card";

const LEADS = [
  { name: "Marcus Yu", service: "AC Repair", source: "Website", temp: "hot" as const },
  { name: "Dana Price", service: "Roof Inspection", source: "Google Ads", temp: "warm" as const },
  { name: "Priya Nair", service: "Water Heater Install", source: "Referral", temp: "warm" as const },
  { name: "Chris Ibe", service: "Duct Cleaning", source: "Facebook Ads", temp: "cold" as const },
];

const APPOINTMENTS = [
  { name: "Marcus Yu", service: "AC Repair", time: "Tomorrow, 9:00 AM" },
  { name: "Priya Nair", service: "Water Heater Install", time: "Thu, 1:30 PM" },
];

export function DashboardPreviewSection() {
  return (
    <section className="border-t border-border bg-background py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            One dashboard, every recovered lead.
          </h2>
          <p className="mt-4 text-lg text-muted">
            See exactly what Converana is doing for your business — in real time.
          </p>
        </div>

        <div className="mx-auto mt-12 grid max-w-5xl grid-cols-2 gap-3 sm:grid-cols-4">
          {/* Illustrative counts only. No revenue figure and no month-over-month
              percentages: under a heading that says "in real time", those read as
              results Converana produced for a real customer, which is a claim we
              can't substantiate. Mirrors the hero preview. */}
          <MetricCard label="Leads" value="142" />
          <MetricCard label="Qualified" value="63" />
          <MetricCard label="Appointments" value="28" />
          <MetricCard label="Follow-ups" value="96" emphasize />
        </div>

        <Card className="mx-auto mt-6 max-w-5xl p-4 sm:p-6">
          <Tabs defaultValue="leads">
            <TabsList>
              <TabsTrigger value="leads">Leads</TabsTrigger>
              <TabsTrigger value="appointments">Appointments</TabsTrigger>
            </TabsList>
            <TabsContent value="leads" className="space-y-1">
              {LEADS.map((lead) => (
                <div
                  key={lead.name}
                  className="flex items-center gap-3 rounded-md px-2 py-2.5 hover:bg-muted-surface"
                >
                  <Avatar name={lead.name} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-foreground">{lead.name}</p>
                    <p className="truncate text-xs text-muted">
                      {lead.service} · {lead.source}
                    </p>
                  </div>
                  <TempBadge temp={lead.temp} />
                </div>
              ))}
            </TabsContent>
            <TabsContent value="appointments" className="space-y-1">
              {APPOINTMENTS.map((appt) => (
                <div
                  key={appt.name}
                  className="flex items-center gap-3 rounded-md px-2 py-2.5 hover:bg-muted-surface"
                >
                  <div className="flex h-9 w-9 items-center justify-center rounded-full bg-success-surface text-success">
                    <Calendar className="h-4 w-4" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-foreground">{appt.name}</p>
                    <p className="truncate text-xs text-muted">{appt.service}</p>
                  </div>
                  <p className="text-xs font-medium text-muted">{appt.time}</p>
                </div>
              ))}
            </TabsContent>
          </Tabs>
        </Card>
      </div>
    </section>
  );
}

function TempBadge({ temp }: { temp: "hot" | "warm" | "cold" }) {
  if (temp === "hot")
    return (
      <Badge variant="hot">
        <Flame className="h-3 w-3" /> Hot
      </Badge>
    );
  if (temp === "warm")
    return (
      <Badge variant="warm">
        <Sun className="h-3 w-3" /> Warm
      </Badge>
    );
  return (
    <Badge variant="cold">
      <Snowflake className="h-3 w-3" /> Cold
    </Badge>
  );
}
