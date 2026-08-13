/**
 * The Lead fields a CSV column can be mapped onto, and the header-name
 * guessing that pre-fills the mapping step.
 *
 * Every key here is a real column on the Lead model — nothing is invented,
 * and AI/qualification fields are deliberately excluded: those are produced
 * by Converana, never supplied by an upload.
 *
 * Pure — no server-only import — so it is shared by the mapping UI and the
 * server-side validator, which guarantees the two can't drift apart.
 */

export const IMPORT_FIELDS = [
  { key: "firstName", label: "First Name", required: true },
  { key: "lastName", label: "Last Name" },
  { key: "email", label: "Email", identifier: true },
  { key: "phone", label: "Phone", identifier: true },
  { key: "serviceRequested", label: "Service Requested" },
  { key: "source", label: "Source" },
  { key: "message", label: "Message" },
  { key: "estimatedValue", label: "Estimated Value" },
  { key: "status", label: "Status" },
  { key: "temperature", label: "Temperature" },
] as const;

export type ImportField = (typeof IMPORT_FIELDS)[number]["key"];

export const IMPORT_FIELD_KEYS: ImportField[] = IMPORT_FIELDS.map((f) => f.key);

export function importFieldLabel(key: ImportField): string {
  return IMPORT_FIELDS.find((f) => f.key === key)?.label ?? key;
}

/**
 * A column mapping: one entry per CSV column, in column order. `null` means
 * "ignore this column".
 */
export type ColumnMapping = (ImportField | null)[];

/**
 * Header aliases, matched after stripping everything that isn't a letter or
 * digit — so "First Name", "first_name", "FIRSTNAME" and "first-name" all
 * collapse to the same key.
 */
const ALIASES: Record<ImportField, string[]> = {
  firstName: [
    "firstname", "first", "fname", "givenname", "forename", "name", "fullname",
    "contactname", "customername", "leadname", "contactfirstname",
  ],
  lastName: ["lastname", "last", "lname", "surname", "familyname", "contactlastname"],
  email: ["email", "emailaddress", "mail", "contactemail", "workemail", "emailid"],
  phone: [
    "phone", "phonenumber", "mobile", "mobilenumber", "telephone", "tel", "cell",
    "cellphone", "contactnumber", "contactphone", "phoneno", "whatsapp",
  ],
  serviceRequested: [
    "servicerequested", "service", "servicetype", "jobtype", "job", "interestedin",
    "product", "requestedservice", "enquirytype", "inquirytype",
  ],
  source: [
    "source", "leadsource", "campaign", "utmsource", "channel", "referrer",
    "referralsource", "medium", "adcampaign",
  ],
  message: [
    "message", "notes", "note", "comment", "comments", "description", "details",
    "enquiry", "inquiry", "request", "body",
  ],
  estimatedValue: [
    "estimatedvalue", "value", "dealvalue", "jobvalue", "amount", "budget",
    "price", "quote", "estimate", "dealsize",
  ],
  status: ["status", "leadstatus", "stage", "leadstage", "pipelinestage"],
  temperature: ["temperature", "temp", "leadtemperature", "priority", "rating", "quality"],
};

function normalizeHeader(header: string): string {
  return header.toLowerCase().replace(/[^a-z0-9]/g, "");
}

/**
 * Guesses a mapping from the CSV's header names. Only a suggestion — the
 * import never runs until the user has seen and confirmed it.
 *
 * A field is only ever suggested once; with both "Name" and "First Name"
 * present, the earlier column wins and the other is left for the user.
 */
export function suggestMapping(headers: string[]): ColumnMapping {
  const taken = new Set<ImportField>();

  // Exact alias matches first, so a later "Email" beats an earlier
  // "Email Opt In" that merely starts with the same word.
  const mapping: ColumnMapping = headers.map(() => null);
  const normalized = headers.map(normalizeHeader);

  for (const pass of ["exact", "prefix"] as const) {
    for (let i = 0; i < headers.length; i++) {
      if (mapping[i]) continue;
      const value = normalized[i];
      if (!value) continue;

      for (const field of IMPORT_FIELD_KEYS) {
        if (taken.has(field)) continue;
        const aliases = ALIASES[field];
        const hit =
          pass === "exact"
            ? aliases.includes(value)
            : aliases.some((alias) => alias.length >= 4 && value.startsWith(alias));
        if (hit) {
          mapping[i] = field;
          taken.add(field);
          break;
        }
      }
    }
  }

  return mapping;
}
