"use client";

import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

const BRAND = "#2451e8";

export function LeadsTrendChart({ data }: { data: { date: string; leads: number }[] }) {
  return (
    <ResponsiveContainer width="100%" height={260}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
        <defs>
          <linearGradient id="leadsFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={BRAND} stopOpacity={0.18} />
            <stop offset="100%" stopColor={BRAND} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid vertical={false} stroke="#e2e8f0" strokeDasharray="3 3" />
        <XAxis
          dataKey="date"
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 11, fill: "#64748b" }}
          interval="preserveStartEnd"
          minTickGap={24}
        />
        <YAxis
          tickLine={false}
          axisLine={false}
          tick={{ fontSize: 11, fill: "#64748b" }}
          width={28}
          allowDecimals={false}
        />
        <Tooltip
          cursor={{ stroke: "#e2e8f0" }}
          contentStyle={{
            fontSize: 12,
            borderRadius: 8,
            border: "1px solid #e2e8f0",
            boxShadow: "0 4px 12px rgba(15,23,42,0.08)",
          }}
          labelStyle={{ color: "#0f172a", fontWeight: 500 }}
        />
        <Area
          type="monotone"
          dataKey="leads"
          name="Leads"
          stroke={BRAND}
          strokeWidth={2}
          fill="url(#leadsFill)"
          dot={false}
          activeDot={{ r: 4 }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
