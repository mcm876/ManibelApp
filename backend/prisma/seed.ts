import bcrypt from 'bcryptjs';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Same demo account DriverSession.ensureDemoAccountSeeded used to seed
 * on-device, so driver login has something real to authenticate against
 * now that the backend owns driver accounts.
 */
async function main() {
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
