export const INDUSTRIES = [
  "HVAC",
  "Plumbing",
  "Roofing",
  "Electrical",
  "Dentistry",
  "Med Spa",
  "Auto Detailing",
  "Cleaning Services",
  "Real Estate",
  "Other Home Service",
] as const;

export const AI_TONES = [
  { value: "professional", label: "Professional", description: "Polished, businesslike, to the point." },
  { value: "friendly", label: "Friendly", description: "Warm and conversational, still efficient." },
  { value: "casual", label: "Casual", description: "Relaxed and informal." },
  { value: "formal", label: "Formal", description: "Reserved and traditional." },
] as const;

export const WEEKDAYS = [
  { key: "mon", label: "Monday" },
  { key: "tue", label: "Tuesday" },
  { key: "wed", label: "Wednesday" },
  { key: "thu", label: "Thursday" },
  { key: "fri", label: "Friday" },
  { key: "sat", label: "Saturday" },
  { key: "sun", label: "Sunday" },
] as const;

export const DEFAULT_BUSINESS_HOURS: Record<string, string> = {
  mon: "8:00 AM - 6:00 PM",
  tue: "8:00 AM - 6:00 PM",
  wed: "8:00 AM - 6:00 PM",
  thu: "8:00 AM - 6:00 PM",
  fri: "8:00 AM - 6:00 PM",
  sat: "Closed",
  sun: "Closed",
};

export const LEAD_SOURCES = [
  { value: "website", label: "Website" },
  { value: "embed", label: "Embedded form" },
  { value: "api", label: "API" },
  { value: "manual", label: "Manual entry" },
  { value: "google_ads", label: "Google Ads" },
  { value: "facebook_ads", label: "Facebook Ads" },
  { value: "referral", label: "Referral" },
  { value: "phone", label: "Phone" },
  { value: "other", label: "Other" },
] as const;
