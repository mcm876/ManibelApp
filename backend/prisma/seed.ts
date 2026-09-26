import bcrypt from 'bcryptjs';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Same demo account DriverSession.ensureDemoAccountSeeded used to seed
 * on-device, so driver login has something real to authenticate against
 * now that the backend owns driver accounts.
 */
const ID_TYPES = [
  { code: 'PHILSYS', label: 'Philippine National ID (PhilSys)', hasExpiry: false },
  { code: 'DRIVERS_LICENSE', label: "Driver's License", hasExpiry: true },
  { code: 'PASSPORT', label: 'Passport', hasExpiry: true },
  { code: 'UMID', label: 'UMID', hasExpiry: true },
  { code: 'VOTERS_ID', label: "Voter's ID", hasExpiry: false },
  { code: 'POSTAL_ID', label: 'Postal ID', hasExpiry: true },
];

async function seedIdTypes() {
  for (const [i, t] of ID_TYPES.entries()) {
    await prisma.governmentIdType.upsert({
      where: { code: t.code },
      update: {},
      create: { ...t, requiresBack: true, sortOrder: i },
    });
  }
  console.log(`Seeded ${ID_TYPES.length} government ID types.`);
}

async function main() {
  await seedIdTypes();
  const mobileNumber = '+639171234567';
  const existing = await prisma.driver.findUnique({ where: { mobileNumber } });
  if (existing) {
    console.log('Demo driver already seeded, skipping.');
    return;
  }

  await prisma.driver.create({
    data: {
      driverId: 'DR-00001',
      fullName: 'Juan Dela Cruz',
      mobileNumber,
      passwordHash: await bcrypt.hash('Driver@123', 10),
      plateNumber: 'NGP-0001',
    },
  });

  console.log(`Seeded demo driver: ${mobileNumber} / Driver@123`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
