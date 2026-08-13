import { getApiAuthContext } from "@/lib/auth/session";
import { apiUnauthorized } from "@/lib/api/response";
import { toCsv } from "@/lib/leads/import/csv";

/**
 * A ready-made example file for the import flow. Entirely fictional: the
 * addresses are on example.com (reserved by RFC 2606) and the numbers are in
 * the 555-01xx range reserved for fiction, so downloading and importing this
 * can never reach a real person.
 */
const SAMPLE_HEADERS = [
  "first_name",
  "last_name",
  "email",
  "phone",
  "service_requested",
  "source",
  "message",
];

const SAMPLE_ROWS = [
  [
    "John",
    "Smith",
    "john.smith@example.com",
    "+12125550123",
    "Roof Repair",
    "Facebook Ads",
    "Need a quote for a leaking roof.",
  ],
  [
    "Sarah",
    "Jones",
    "sarah.jones@example.com",
    "+12125550124",
    "HVAC",
    "Google Ads",
    "AC stopped working over the weekend.",
  ],
  [
    "Miguel",
    "Alvarez",
    "miguel.alvarez@example.com",
    "+12125550125",
    "Drain Cleaning",
    "Referral",
    "Kitchen sink drains very slowly.",
  ],
  ["Priya", "Patel", "priya.patel@example.com", "", "Water Heater", "Website", "Looking for a replacement quote."],
  ["Dana", "Whitfield", "", "+12125550127", "Gutter Cleaning", "Referral", "Gutters overflowing after storms."],
];

export async function GET() {
  const auth = await getApiAuthContext();
  if (!auth) return apiUnauthorized();

  // `trusted` — this content is authored here, and the formula guard would
  // otherwise rewrite the E.164 numbers as text-escaped `'+1…`, which is the
  // one thing a file meant to be re-uploaded must not do.
  return new Response(toCsv(SAMPLE_HEADERS, SAMPLE_ROWS, { trusted: true }), {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": 'attachment; filename="converana-sample-leads.csv"',
      "Cache-Control": "no-store",
    },
  });
}
