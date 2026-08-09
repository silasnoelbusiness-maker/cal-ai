import type { Metadata } from "next";
import { KeyRound } from "lucide-react";
import { requireBusiness } from "@/lib/auth/session";
import { prisma } from "@/lib/db/prisma";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { CreateApiKeyDialog } from "@/components/settings/create-api-key-dialog";
import { RevokeApiKeyButton } from "@/components/settings/revoke-api-key-button";
import { formatDate, formatRelativeTime } from "@/lib/utils";

export const metadata: Metadata = { title: "API Keys" };

export default async function ApiKeysPage() {
  const { business } = await requireBusiness();
  const keys = await prisma.apiKey.findMany({
    where: { businessId: business.id, revokedAt: null },
    orderBy: { createdAt: "desc" },
  });

  return (
    <Card>
      <CardHeader className="flex-row items-center justify-between space-y-0">
        <div>
          <CardTitle>API keys</CardTitle>
          <CardDescription>
            Authenticate requests to the lead capture API with{" "}
            <code className="rounded bg-muted-surface px-1 py-0.5 text-xs">Authorization: Bearer &lt;key&gt;</code>.
          </CardDescription>
        </div>
        <CreateApiKeyDialog />
      </CardHeader>
      <CardContent>
        {keys.length === 0 ? (
          <EmptyState
            icon={KeyRound}
            title="No API keys yet"
            description="Create a key to send leads into LeadLoop from an external form, CRM, or ad platform."
            className="border-0 py-10"
          />
        ) : (
          <div className="divide-y divide-border">
            {keys.map((key) => (
              <div key={key.id} className="flex items-center justify-between gap-3 py-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-foreground">{key.name}</p>
                  <p className="truncate font-mono text-xs text-muted">
                    {key.keyPrefix}••••••••
                  </p>
                  <p className="text-xs text-muted">
                    Created {formatDate(key.createdAt)}
                    {key.lastUsedAt ? ` · Last used ${formatRelativeTime(key.lastUsedAt)}` : " · Never used"}
                  </p>
                </div>
                <RevokeApiKeyButton keyId={key.id} keyName={key.name} />
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
