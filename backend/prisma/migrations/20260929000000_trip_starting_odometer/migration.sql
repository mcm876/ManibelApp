-- AlterTable: the odometer reading (km) the driver enters before starting a
-- trip, and the vehicle's plate at that moment. Both nullable: trips from
-- before this existed have no reading, and "no earlier reading" just means
-- nothing to compare against. The plate is backfilled from the driver's
-- current plate so existing trips still count as that vehicle's history.
ALTER TABLE "Trip" ADD COLUMN "startingOdometer" DOUBLE PRECISION,
ADD COLUMN "plateNumber" TEXT;

UPDATE "Trip" SET "plateNumber" = "Driver"."plateNumber"
FROM "Driver" WHERE "Trip"."driverId" = "Driver"."id";

-- CreateIndex
CREATE INDEX "Trip_plateNumber_startedAt_idx" ON "Trip"("plateNumber", "startedAt");
