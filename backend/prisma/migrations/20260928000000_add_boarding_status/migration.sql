-- CreateEnum
CREATE TYPE "BoardingStatus" AS ENUM ('BOARDED', 'COMPLETED', 'CANCELLED');

-- AlterTable — a boarding row now says outright whether the commuter is
-- still on board, finished the ride, or cancelled it (boarded but never
-- actually rode). [cancelledAt] is set only for CANCELLED.
ALTER TABLE "TripBoarding" ADD COLUMN "status" "BoardingStatus" NOT NULL DEFAULT 'BOARDED',
ADD COLUMN "cancelledAt" TIMESTAMP(3);

-- Backfill — every boarding that was already closed out (alightedAt set,
-- whether by the commuter's own "Para Po" or the driver ending the trip) is
-- a completed ride; the DEFAULT above already left the still-open ones as
-- BOARDED.
UPDATE "TripBoarding" SET "status" = 'COMPLETED' WHERE "alightedAt" IS NOT NULL;
