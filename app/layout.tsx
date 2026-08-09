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
    default: "LeadLoop — Turn Missed Leads Into Booked Customers",
    template: "%s — LeadLoop",
  },
  description:
    "AI-powered lead follow-up for local businesses. Automatically respond to new leads, qualify prospects, and help turn more conversations into booked customers.",
  icons: {
    icon: "/icon.svg",
  },
  openGraph: {
    title: "LeadLoop — Turn Missed Leads Into Booked Customers",
    description:
      "AI-powered lead follow-up for local businesses. Automatically respond to new leads, qualify prospects, and help turn more conversations into booked customers.",
    url: appUrl,
    siteName: "LeadLoop",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "LeadLoop — Turn Missed Leads Into Booked Customers",
    description:
      "AI-powered lead follow-up for local businesses. Automatically respond to new leads, qualify prospects, and help turn more conversations into booked customers.",
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
