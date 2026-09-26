-- CreateEnum
CREATE TYPE "IdVerificationStatus" AS ENUM ('NONE', 'PENDING_REVIEW', 'VERIFIED');

-- CreateEnum
CREATE TYPE "IdSubmissionStatus" AS ENUM ('APPROVED', 'PENDING_REVIEW', 'REJECTED');

-- AlterTable
ALTER TABLE "Commuter" ADD COLUMN     "idVerificationStatus" "IdVerificationStatus" NOT NULL DEFAULT 'NONE';

-- CreateTable
CREATE TABLE "GovernmentIdType" (
    "id" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "hasExpiry" BOOLEAN NOT NULL DEFAULT true,
    "requiresBack" BOOLEAN NOT NULL DEFAULT true,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "GovernmentIdType_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IdSubmission" (
    "id" TEXT NOT NULL,
    "commuterId" TEXT NOT NULL,
    "idTypeId" TEXT NOT NULL,
    "birthDate" TIMESTAMP(3),
    "expiryDate" TIMESTAMP(3),
    "faceMatchScore" DOUBLE PRECISION,
    "status" "IdSubmissionStatus" NOT NULL,
    "reviewReasons" TEXT[],
    "frontPath" TEXT NOT NULL,
    "backPath" TEXT,
    "selfiePath" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IdSubmission_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "GovernmentIdType_code_key" ON "GovernmentIdType"("code");

-- CreateIndex
CREATE INDEX "IdSubmission_commuterId_idx" ON "IdSubmission"("commuterId");

-- AddForeignKey
ALTER TABLE "IdSubmission" ADD CONSTRAINT "IdSubmission_commuterId_fkey" FOREIGN KEY ("commuterId") REFERENCES "Commuter"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IdSubmission" ADD CONSTRAINT "IdSubmission_idTypeId_fkey" FOREIGN KEY ("idTypeId") REFERENCES "GovernmentIdType"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

