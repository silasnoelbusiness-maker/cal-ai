import type { Metadata } from "next";
import { Users } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { buildLeadsWhere, buildLeadsOrderBy, LEADS_PAGE_SIZE, type LeadFilter } from "@/lib/leads/query";
import { PageHeader } from "@/components/dashboard/page-header";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { LeadsFilters } from "@/components/leads/leads-filters";
import { LeadsSearch } from "@/components/leads/leads-search";
import { LeadsTable } from "@/components/leads/leads-table";
import { NewLeadDialog } from "@/components/leads/new-lead-dialog";
import { AddTestLeadButton } from "@/components/dashboard/add-test-lead-button";
import { Pagination } from "@/components/ui/pagination";

export const metadata: Metadata = { title: "Leads" };

export default async function LeadsPage({ searchParams }: PageProps<"/dashboard/leads">) {
  const { business } = await requireBusiness();
  const params = await searchParams;

  const filter = typeof params.filter === "string" ? params.filter : "all";
  const q = typeof params.q === "string" ? params.q : "";
  const sort = typeof params.sort === "string" ? params.sort : "createdAt";
  const dir = typeof params.dir === "string" ? params.dir : "desc";
  const page = Math.max(Number(params.page) || 1, 1);

  const where = buildLeadsWhere({ businessId: business.id, filter, q });
  const orderBy = buildLeadsOrderBy({ businessId: business.id, sort, dir });

  const [leads, total, totalAllLeads, statusGroups, tempGroups] = await Promise.all([
    prisma.lead.findMany({
      where,
      orderBy,
      skip: (page - 1) * LEADS_PAGE_SIZE,
      take: LEADS_PAGE_SIZE,
    }),
    prisma.lead.count({ where }),
    prisma.lead.count({ where: { businessId: business.id } }),
    prisma.lead.groupBy({ by: ["status"], where: { businessId: business.id }, _count: { _all: true } }),
    prisma.lead.groupBy({ by: ["temperature"], where: { businessId: business.id }, _count: { _all: true } }),
  ]);

  const counts: Partial<Record<LeadFilter, number>> = { all: totalAllLeads };
  for (const g of statusGroups) counts[g.status.toLowerCase() as LeadFilter] = g._count._all;
  for (const g of tempGroups) counts[g.temperature.toLowerCase() as LeadFilter] = g._count._all;

  function buildHref(overrides: Record<string, string | number | undefined>) {
    const sp = new URLSearchParams();
    if (filter !== "all") sp.set("filter", filter);
    if (q) sp.set("q", q);
    if (sort !== "createdAt") sp.set("sort", sort);
    if (dir !== "desc") sp.set("dir", dir);
    if (page !== 1) sp.set("page", String(page));
    for (const [key, value] of Object.entries(overrides)) {
      if (value === undefined) sp.delete(key);
      else sp.set(key, String(value));
    }
    const qs = sp.toString();
    return `/dashboard/leads${qs ? `?${qs}` : ""}`;
  }

  return (
    <div>
      <PageHeader
        title="Leads"
        description="Every lead captured across your sources, qualified and prioritized automatically."
        actions={<NewLeadDialog />}
      />

      {totalAllLeads === 0 ? (
        <EmptyState
          icon={Users}
          title="No leads yet"
          description="Connect your website form or create your first lead to see Converana in action."
          action={<AddTestLeadButton />}
        />
      ) : (
        <Card>
          <div className="flex flex-col gap-3 border-b border-border p-4 sm:flex-row sm:items-center sm:justify-between">
            <LeadsFilters counts={counts} />
            <LeadsSearch />
          </div>

          {leads.length === 0 ? (
            <EmptyState
              title="No leads match your filters"
              description="Try a different filter or clear your search."
              className="border-0"
            />
          ) : (
            <LeadsTable
              leads={leads}
              currentSort={sort}
              currentDir={dir}
              buildSortHref={(newSort) =>
                buildHref({
                  sort: newSort,
                  dir: sort === newSort && dir === "desc" ? "asc" : "desc",
                })
              }
            />
          )}

          <Pagination
            page={page}
            pageSize={LEADS_PAGE_SIZE}
            total={total}
            buildHref={(p) => buildHref({ page: p === 1 ? undefined : p })}
          />
        </Card>
      )}
    </div>
  );
}
