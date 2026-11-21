-- Presence check after boarding: auto-remove commuters who never rode along.
ALTER TABLE "TripBoarding"
  ADD COLUMN "boardedLat" DOUBLE PRECISION,
  ADD COLUMN "boardedLng" DOUBLE PRECISION,
  ADD COLUMN "jeepLatAtBoard" DOUBLE PRECISION,
  ADD COLUMN "jeepLngAtBoard" DOUBLE PRECISION,
  ADD COLUMN "ridingVerifiedAt" TIMESTAMP(3),
  ADD COLUMN "awayReadings" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "awaySince" TIMESTAMP(3),
  ADD COLUMN "lastPresenceAt" TIMESTAMP(3),
  ADD COLUMN "releasedReason" TEXT;
