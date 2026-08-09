"use client";

import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

const BRAND = "#2451e8";

export function FunnelChart({ data }: { data: { stage: string; count: number }[] }) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={data} layout="vertical" margin={{ top: 4, right: 16, left: 8, bottom: 0 }}>
        <CartesianGrid horizontal={false} stroke="#e2e8f0" strokeDasharray="3 3" />
        <XAxis type="number" tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: "#64748b" }} allowDecimals={false} />
        <YAxis
          type="category"
          dataKey="stage"
          tickLine={false}
          axisLine={false}
          width={84}
          tick={{ fontSize: 12, fill: "#0f172a" }}
        />
        <Tooltip
          cursor={{ fill: "#f1f5f9" }}
          contentStyle={{
            fontSize: 12,
            borderRadius: 8,
            border: "1px solid #e2e8f0",
            boxShadow: "0 4px 12px rgba(15,23,42,0.08)",
          }}
        />
        <Bar dataKey="count" name="Leads" radius={[0, 4, 4, 0]} maxBarSize={22}>
          {data.map((entry, index) => (
            <Cell key={entry.stage} fillOpacity={1 - index * 0.12} fill={BRAND} />
          ))}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}
