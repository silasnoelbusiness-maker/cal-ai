"use client";

import { useEffect } from "react";

/**
 * Last-resort error boundary — only fires if the root layout itself throws
 * (e.g. a layout-level data fetch fails), which app/error.tsx cannot catch
 * since it renders *inside* the root layout. Per Next.js's contract this
 * must render its own <html>/<body> since it replaces the root layout
 * entirely, so it intentionally avoids relying on globals.css or any other
 * app infrastructure that may itself be the thing that broke.
 */
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error("[app] root layout error", error);
  }, [error]);

  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          minHeight: "100vh",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          fontFamily: "system-ui, -apple-system, sans-serif",
          textAlign: "center",
          padding: "24px",
          background: "#f8fafc",
          color: "#0f172a",
        }}
      >
        <h1 style={{ fontSize: 18, fontWeight: 600, margin: 0 }}>Something went wrong</h1>
        <p style={{ marginTop: 8, maxWidth: 380, fontSize: 14, color: "#64748b" }}>
          LeadLoop hit an unexpected error and couldn&apos;t load. Please try again.
        </p>
        <button
          onClick={() => reset()}
          style={{
            marginTop: 20,
            padding: "8px 16px",
            borderRadius: 6,
            border: "none",
            background: "#2451e8",
            color: "#fff",
            fontSize: 14,
            fontWeight: 500,
            cursor: "pointer",
          }}
        >
          Try again
        </button>
      </body>
    </html>
  );
}
