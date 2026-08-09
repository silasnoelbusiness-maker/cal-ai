import { PageHeader } from "@/components/dashboard/page-header";
import { SettingsNav } from "@/components/settings/settings-nav";

export default function SettingsLayout({ children }: { children: React.ReactNode }) {
  return (
    <div>
      <PageHeader title="Settings" description="Manage your business, AI assistant, and account." />
      <SettingsNav />
      <div className="mt-6 max-w-2xl">{children}</div>
    </div>
  );
}
