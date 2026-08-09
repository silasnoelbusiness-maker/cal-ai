const CONFIG = {
  HOT: { label: "Hot", color: "var(--hot)" },
  WARM: { label: "Warm", color: "var(--warm)" },
  COLD: { label: "Cold", color: "var(--cold)" },
} as const;

export function TemperatureBreakdown({
  data,
}: {
  data: { temperature: "HOT" | "WARM" | "COLD"; count: number }[];
}) {
  const total = data.reduce((sum, d) => sum + d.count, 0);

  return (
    <div>
      <div className="flex h-2.5 w-full overflow-hidden rounded-full bg-muted-surface">
        {data.map((d) => {
          const pct = total > 0 ? (d.count / total) * 100 : 0;
          if (pct === 0) return null;
          return (
            <div
              key={d.temperature}
              style={{ width: `${pct}%`, backgroundColor: CONFIG[d.temperature].color }}
              title={`${CONFIG[d.temperature].label}: ${d.count}`}
            />
          );
        })}
      </div>
      <div className="mt-4 grid grid-cols-3 gap-3">
        {data.map((d) => (
          <div key={d.temperature} className="flex items-center gap-2">
            <span
              className="h-2.5 w-2.5 shrink-0 rounded-full"
              style={{ backgroundColor: CONFIG[d.temperature].color }}
            />
            <div>
              <p className="text-sm font-medium text-foreground">{d.count}</p>
              <p className="text-xs text-muted">{CONFIG[d.temperature].label}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
