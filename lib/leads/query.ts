import type { Prisma, LeadStatus, LeadTemperature } from "@prisma/client";

export const LEAD_FILTERS = [
  "all",
  "new",
  "hot",
  "warm",
  "cold",
  "qualified",
  "appointment",
  "converted",
  "lost",
] as const;
export type LeadFilter = (typeof LEAD_FILTERS)[number];

const STATUS_FILTERS = new Set<string>(["new", "qualified", "appointment", "converted", "lost"]);
const TEMP_FILTERS = new Set<string>(["hot", "warm", "cold"]);

export const LEAD_SORTS = ["createdAt", "lastContactedAt", "estimatedValue", "qualificationScore"] as const;
export type LeadSort = (typeof LEAD_SORTS)[number];

export interface LeadsQueryParams {
  businessId: string;
  filter?: string;
  q?: string;
  sort?: string;
  dir?: string;
  page?: number;
  pageSize?: number;
}

export function buildLeadsWhere(params: LeadsQueryParams): Prisma.LeadWhereInput {
  const where: Prisma.LeadWhereInput = { businessId: params.businessId };

  const filter = (params.filter || "all").toLowerCase();
  if (STATUS_FILTERS.has(filter)) {
    where.status = filter.toUpperCase() as LeadStatus;
  } else if (TEMP_FILTERS.has(filter)) {
    where.temperature = filter.toUpperCase() as LeadTemperature;
  }

  const q = params.q?.trim();
  if (q) {
    where.OR = [
      { firstName: { contains: q, mode: "insensitive" } },
      { lastName: { contains: q, mode: "insensitive" } },
      { email: { contains: q, mode: "insensitive" } },
      { phone: { contains: q, mode: "insensitive" } },
      { serviceRequested: { contains: q, mode: "insensitive" } },
      { message: { contains: q, mode: "insensitive" } },
      { conversations: { some: { messages: { some: { content: { contains: q, mode: "insensitive" } } } } } },
    ];
  }

  return where;
}

export function buildLeadsOrderBy(params: LeadsQueryParams): Prisma.LeadOrderByWithRelationInput {
  const sort = LEAD_SORTS.includes(params.sort as LeadSort) ? (params.sort as LeadSort) : "createdAt";
  const dir = params.dir === "asc" ? "asc" : "desc";
  return { [sort]: dir };
}

export const LEADS_PAGE_SIZE = 20;
