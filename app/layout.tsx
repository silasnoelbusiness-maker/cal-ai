import type { Metadata } from "next";
import { Inter } from "next/font/google";
import { Toaster } from "sonner";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(appUrl),
  title: {
    default: "Converana — Turn Missed Leads Into Booked Jobs",
    template: "%s — Converana",
  },
  description:
    "Converana answers new and missed leads for home-service businesses, qualifies them with AI, and alerts your team when a lead is ready to book. No credit card required.",
  applicationName: "Converana",
  keywords: [
    "lead follow-up software",
    "home service leads",
    "AI lead qualification",
    "missed lead recovery",
    "HVAC lead management",
  ],
  icons: {
    icon: "/icon.svg",
    apple: "/icon.svg",
  },
  robots: { index: true, follow: true },
  openGraph: {
    title: "Converana — Turn Missed Leads Into Booked Jobs",
    description:
      "Converana answers new and missed leads for home-service businesses, qualifies them with AI, and alerts your team when a lead is ready to book.",
    url: appUrl,
    siteName: "Converana",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Converana — Turn Missed Leads Into Booked Jobs",
    description:
      "Converana answers new and missed leads for home-service businesses, qualifies them with AI, and alerts your team when a lead is ready to book.",
  },
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${inter.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col bg-background text-foreground">
        {children}
        <Toaster position="top-right" richColors closeButton />
      </body>
    </html>
  );
}
