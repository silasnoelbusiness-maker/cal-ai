-- AlterTable
ALTER TABLE "subscriptions" ADD COLUMN     "whop_last_event_at" TIMESTAMP(3),
ADD COLUMN     "whop_membership_id" TEXT,
ADD COLUMN     "whop_plan_id" TEXT,
ADD COLUMN     "whop_user_id" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "subscriptions_whop_membership_id_key" ON "subscriptions"("whop_membership_id");

