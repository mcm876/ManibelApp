-- Heals existing drift: Driver.selfieUrl was never given a migration.
ALTER TABLE "Driver" ADD COLUMN IF NOT EXISTS "selfieUrl" TEXT;

-- CreateEnum
CREATE TYPE "OperationalStatus" AS ENUM ('ACTIVE', 'INACTIVE');

-- CreateEnum
CREATE TYPE "DisciplinaryStatus" AS ENUM ('NONE', 'WARNING', 'UNDER_INVESTIGATION', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "BoardingRequestStatus" AS ENUM ('PENDING', 'CONFIRMED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "ShortTripIncidentStatus" AS ENUM ('PENDING_EXPLANATION', 'EXPLAINED', 'UNDER_REVIEW', 'CONFIRMED', 'DISMISSED', 'DUPLICATE');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "AdminRole" ADD VALUE 'OPERATOR';
ALTER TYPE "AdminRole" ADD VALUE 'MANIBELA';

-- AlterTable
ALTER TABLE "Complaint" ADD COLUMN     "actionTaken" TEXT,
ADD COLUMN     "investigationNotes" TEXT,
ADD COLUMN     "resolution" TEXT,
ADD COLUMN     "reviewedAt" TIMESTAMP(3),
ADD COLUMN     "reviewedById" TEXT,
ADD COLUMN     "sanction" TEXT;

-- AlterTable
ALTER TABLE "Driver" ADD COLUMN     "disciplinaryStatus" "DisciplinaryStatus" NOT NULL DEFAULT 'NONE',
ADD COLUMN     "operationalStatus" "OperationalStatus" NOT NULL DEFAULT 'ACTIVE',
ADD COLUMN     "operatorId" TEXT;

-- AlterTable
ALTER TABLE "DriverDailyLog" ADD COLUMN     "verificationNote" TEXT,
ADD COLUMN     "verifiedAt" TIMESTAMP(3),
ADD COLUMN     "verifiedById" TEXT,
ADD COLUMN     "verifiedEarnings" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "Trip" ADD COLUMN     "capacitySnapshot" INTEGER,
ADD COLUMN     "manualPassengers" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "peakOccupancy" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "vehicleId" TEXT;

-- AlterTable
ALTER TABLE "TripBoarding" ADD COLUMN     "requestId" TEXT;

-- CreateTable
CREATE TABLE "Vehicle" (
    "id" TEXT NOT NULL,
    "plateNumber" TEXT NOT NULL,
    "seatingCapacity" INTEGER,
    "operatorId" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Vehicle_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DriverVehicleAssignment" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "vehicleId" TEXT NOT NULL,
    "assignedById" TEXT,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revokedAt" TIMESTAMP(3),
    "revokedById" TEXT,

    CONSTRAINT "DriverVehicleAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "BoardingRequest" (
    "id" TEXT NOT NULL,
    "commuterId" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "vehicleId" TEXT,
    "riders" INTEGER NOT NULL DEFAULT 1,
    "status" "BoardingRequestStatus" NOT NULL DEFAULT 'PENDING',
    "clientRequestId" TEXT,
    "readings" JSONB NOT NULL DEFAULT '[]',
    "consecutiveOk" INTEGER NOT NULL DEFAULT 0,
    "failureCode" TEXT,
    "failureMessage" TEXT,
    "boardingId" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),

    CONSTRAINT "BoardingRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ManualPassengerAdjustment" (
    "id" TEXT NOT NULL,
    "tripId" TEXT NOT NULL,
    "vehicleId" TEXT,
    "driverId" TEXT NOT NULL,
    "delta" INTEGER NOT NULL,
    "countAfter" INTEGER NOT NULL,
    "undoOfId" TEXT,
    "clientRequestId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ManualPassengerAdjustment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SystemSetting" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updatedById" TEXT,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "SystemSetting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "ShortTripIncident" (
    "id" TEXT NOT NULL,
    "tripId" TEXT,
    "driverId" TEXT NOT NULL,
    "vehicleId" TEXT,
    "route" TEXT,
    "intendedDestination" TEXT,
    "source" TEXT NOT NULL,
    "complaintId" TEXT,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "lat" DOUBLE PRECISION,
    "lng" DOUBLE PRECISION,
    "description" TEXT,
    "status" "ShortTripIncidentStatus" NOT NULL DEFAULT 'PENDING_EXPLANATION',
    "explanation" TEXT,
    "explanationSubmittedAt" TIMESTAMP(3),
    "reviewedById" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewNote" TEXT,
    "restrictionId" TEXT,
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ShortTripIncident_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DriverRestriction" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "startsAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "durationMinutes" INTEGER NOT NULL,
    "appliedById" TEXT,
    "incidentIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "liftedAt" TIMESTAMP(3),
    "liftedById" TEXT,
    "liftNote" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DriverRestriction_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditLog" (
    "id" TEXT NOT NULL,
    "actorType" TEXT NOT NULL,
    "actorId" TEXT,
    "action" TEXT NOT NULL,
    "targetType" TEXT NOT NULL,
    "targetId" TEXT,
    "details" JSONB,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "DriverNonOperationDay" (
    "id" TEXT NOT NULL,
    "driverId" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DriverNonOperationDay_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Vehicle_plateNumber_key" ON "Vehicle"("plateNumber");

-- CreateIndex
CREATE INDEX "Vehicle_operatorId_idx" ON "Vehicle"("operatorId");

-- CreateIndex
CREATE INDEX "DriverVehicleAssignment_driverId_revokedAt_idx" ON "DriverVehicleAssignment"("driverId", "revokedAt");

-- CreateIndex
CREATE INDEX "DriverVehicleAssignment_vehicleId_revokedAt_idx" ON "DriverVehicleAssignment"("vehicleId", "revokedAt");

-- CreateIndex
CREATE INDEX "BoardingRequest_tripId_status_idx" ON "BoardingRequest"("tripId", "status");

-- CreateIndex
CREATE INDEX "BoardingRequest_commuterId_status_idx" ON "BoardingRequest"("commuterId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "BoardingRequest_commuterId_clientRequestId_key" ON "BoardingRequest"("commuterId", "clientRequestId");

-- CreateIndex
CREATE UNIQUE INDEX "ManualPassengerAdjustment_undoOfId_key" ON "ManualPassengerAdjustment"("undoOfId");

-- CreateIndex
CREATE INDEX "ManualPassengerAdjustment_tripId_createdAt_idx" ON "ManualPassengerAdjustment"("tripId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "ManualPassengerAdjustment_driverId_clientRequestId_key" ON "ManualPassengerAdjustment"("driverId", "clientRequestId");

-- CreateIndex
CREATE UNIQUE INDEX "ShortTripIncident_complaintId_key" ON "ShortTripIncident"("complaintId");

-- CreateIndex
CREATE INDEX "ShortTripIncident_driverId_status_idx" ON "ShortTripIncident"("driverId", "status");

-- CreateIndex
CREATE INDEX "ShortTripIncident_status_createdAt_idx" ON "ShortTripIncident"("status", "createdAt");

-- CreateIndex
CREATE INDEX "DriverRestriction_driverId_expiresAt_idx" ON "DriverRestriction"("driverId", "expiresAt");

-- CreateIndex
CREATE INDEX "AuditLog_targetType_targetId_createdAt_idx" ON "AuditLog"("targetType", "targetId", "createdAt");

-- CreateIndex
CREATE INDEX "AuditLog_createdAt_idx" ON "AuditLog"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "DriverNonOperationDay_driverId_date_key" ON "DriverNonOperationDay"("driverId", "date");

-- CreateIndex
CREATE INDEX "Driver_operatorId_idx" ON "Driver"("operatorId");

-- CreateIndex
CREATE INDEX "Trip_vehicleId_status_idx" ON "Trip"("vehicleId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "TripBoarding_requestId_key" ON "TripBoarding"("requestId");

-- AddForeignKey
ALTER TABLE "Trip" ADD CONSTRAINT "Trip_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "DriverVehicleAssignment" ADD CONSTRAINT "DriverVehicleAssignment_vehicleId_fkey" FOREIGN KEY ("vehicleId") REFERENCES "Vehicle"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- Rules Prisma cannot express ------------------------------------------------

ALTER TABLE "Trip" ADD CONSTRAINT "Trip_manualPassengers_nonneg" CHECK ("manualPassengers" >= 0);
ALTER TABLE "Vehicle" ADD CONSTRAINT "Vehicle_seatingCapacity_positive" CHECK ("seatingCapacity" IS NULL OR "seatingCapacity" > 0);

-- A jeepney can't be on two ACTIVE trips at once (backstop for the app-level check).
CREATE UNIQUE INDEX "Trip_one_active_per_vehicle" ON "Trip"("vehicleId") WHERE "status" = 'ACTIVE' AND "vehicleId" IS NOT NULL;

-- One open assignment per driver+vehicle pair.
CREATE UNIQUE INDEX "DriverVehicleAssignment_one_open" ON "DriverVehicleAssignment"("driverId", "vehicleId") WHERE "revokedAt" IS NULL;

-- A commuter has at most one pending boarding request at a time.
CREATE UNIQUE INDEX "BoardingRequest_one_pending_per_commuter" ON "BoardingRequest"("commuterId") WHERE "status" = 'PENDING';

-- Backfill (non-destructive): turn each driver's existing plate into a Vehicle
-- + assignment so nobody loses access. Capacity stays NULL on purpose — an
-- operator must enter the real registered capacity.
INSERT INTO "Vehicle" ("id", "plateNumber", "updatedAt")
SELECT 'veh_' || substr(md5(p."plateNumber"), 1, 24), p."plateNumber", CURRENT_TIMESTAMP
FROM (SELECT DISTINCT "plateNumber" FROM "Driver" WHERE "plateNumber" IS NOT NULL AND "plateNumber" <> '') p
ON CONFLICT ("plateNumber") DO NOTHING;

INSERT INTO "DriverVehicleAssignment" ("id", "driverId", "vehicleId")
SELECT 'dva_' || substr(md5(d."id" || v."id"), 1, 24), d."id", v."id"
FROM "Driver" d
JOIN "Vehicle" v ON v."plateNumber" = d."plateNumber";

-- Attribute finished historical trips to their vehicle. ACTIVE trips are left
-- without a vehicle (they predate vehicle selection and end normally).
UPDATE "Trip" t SET "vehicleId" = v."id"
FROM "Vehicle" v
WHERE t."plateNumber" = v."plateNumber" AND t."status" = 'COMPLETED' AND t."vehicleId" IS NULL;
