-- AlterTable
ALTER TABLE "Commuter" ADD COLUMN     "idBirthDate" DATE,
ADD COLUMN     "idExpiryDate" DATE,
ADD COLUMN     "reviewReasons" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "PendingCommuterSignup" ADD COLUMN     "idBirthDate" DATE,
ADD COLUMN     "idExpiryDate" DATE;

-- CreateTable
CREATE TABLE "GovernmentIdType" (
    "id" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "hasExpiry" BOOLEAN NOT NULL DEFAULT true,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "GovernmentIdType_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "GovernmentIdType_label_key" ON "GovernmentIdType"("label");


-- Default ID types (same list the app used to hardcode). gen_random_uuid()
-- is built in from PostgreSQL 13; the ids only need to be unique.
INSERT INTO "GovernmentIdType" ("id", "label", "hasExpiry", "active", "sortOrder") VALUES
  (gen_random_uuid()::text, 'Philippine National ID (PhilSys)', false, true, 0),
  (gen_random_uuid()::text, 'Driver''s License',                 true,  true, 1),
  (gen_random_uuid()::text, 'Passport',                          true,  true, 2),
  (gen_random_uuid()::text, 'UMID',                              true,  true, 3),
  (gen_random_uuid()::text, 'Voter''s ID',                       false, true, 4),
  (gen_random_uuid()::text, 'Postal ID',                         true,  true, 5);
