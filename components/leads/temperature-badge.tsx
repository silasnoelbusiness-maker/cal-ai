import type { LeadTemperature } from "@prisma/client";
import { Flame, Sun, Snowflake } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

const TEMP_CONFIG: Record<
  LeadTemperature,
  { label: string; variant: "hot" | "warm" | "cold"; icon: typeof Flame }
> = {
  HOT: { label: "Hot", variant: "hot", icon: Flame },
  WARM: { label: "Warm", variant: "warm", icon: Sun },
  COLD: { label: "Cold", variant: "cold", icon: Snowflake },
};

export function TemperatureBadge({
  temperature,
  className,
}: {
  temperature: LeadTemperature;
  className?: string;
}) {
  const config = TEMP_CONFIG[temperature];
  const Icon = config.icon;
  return (
    <Badge variant={config.variant} className={cn(className)}>
      <Icon className="h-3 w-3" />
      {config.label}
    </Badge>
  );
}
