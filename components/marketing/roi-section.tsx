import { RoiCalculator } from "./roi-calculator";

export function RoiSection() {
  return (
    <section className="bg-background py-20 sm:py-24">
      <div className="mx-auto max-w-6xl px-4 sm:px-6">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-semibold tracking-tight text-foreground">
            One extra customer can pay for Converana.
          </h2>
          <p className="mt-4 text-lg text-muted">
            See what recovering a few more leads each month could mean for your business.
          </p>
        </div>
        <div className="mt-12">
          <RoiCalculator />
        </div>
      </div>
    </section>
  );
}
