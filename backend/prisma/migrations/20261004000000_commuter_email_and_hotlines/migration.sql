-- AlterTable
ALTER TABLE "Commuter" ADD COLUMN "email" TEXT;

-- AlterTable
ALTER TABLE "PendingCommuterSignup" ADD COLUMN "email" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Commuter_email_key" ON "Commuter"("email");

-- CreateTable
CREATE TABLE "EmergencyHotline" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "number" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "category" TEXT NOT NULL DEFAULT 'other',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "EmergencyHotline_pkey" PRIMARY KEY ("id")
);

-- Default hotlines (the list the app used to hardcode).
INSERT INTO "EmergencyHotline" ("id", "name", "number", "description", "category", "active", "sortOrder") VALUES
  (gen_random_uuid()::text, 'National Emergency Hotline', '911',            'Police, fire, and medical emergencies',        'emergency', true, 0),
  (gen_random_uuid()::text, 'Philippine National Police', '117',            'Report crimes or request police assistance',   'police',    true, 1),
  (gen_random_uuid()::text, 'Bureau of Fire Protection',  '(02) 8426-0219', 'Fire emergencies and rescue',                  'fire',      true, 2),
  (gen_random_uuid()::text, 'Red Cross Ambulance',        '143',            'Medical emergencies and ambulance dispatch',   'medical',   true, 3),
  (gen_random_uuid()::text, 'LTFRB Hotline',              '1342',           'Report jeepney or driver violations',          'transport', true, 4);
