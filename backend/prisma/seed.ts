import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { prisma } from '../src/lib/prisma';
import { generateQrToken } from '../src/utils/qrToken';

// Seeds demo accounts so there's something real to log into without
// having to run create-driver.ts / create-commuter.ts by hand first.
// Safe to re-run: accounts whose mobile number already exists are skipped.
//
// Drivers:   password Driver@123  (mobile numbers +63917123456x)
// Commuters: password Commuter@123 (mobile numbers +63918123456x)

const DRIVER_PASSWORD = 'Driver@123';
const COMMUTER_PASSWORD = 'Commuter@123';

const drivers = [
  { driverId: 'DR-00001', fullName: 'Juan Dela Cruz', mobileNumber: '+639171234567', plateNumber: 'NGP123', licenseNumber: 'N01-23-456781' },
  { driverId: 'DR-00002', fullName: 'Pedro Santos', mobileNumber: '+639171234568', plateNumber: 'NGP234', licenseNumber: 'N02-24-567892' },
  { driverId: 'DR-00003', fullName: 'Ramon Bautista', mobileNumber: '+639171234569', plateNumber: 'NGP345', licenseNumber: 'N03-25-678903' },
  { driverId: 'DR-00004', fullName: 'Eduardo Villanueva', mobileNumber: '+639171234570', plateNumber: 'NGP456', licenseNumber: 'N04-22-789014' },
  { driverId: 'DR-00005', fullName: 'Carlos Mendoza', mobileNumber: '+639171234571', plateNumber: 'NGP567', licenseNumber: 'N05-21-890125' },
];

const commuters = [
  { commuterId: 'CM-00001', fullName: 'Maria Clara Reyes', mobileNumber: '+639181234567', email: 'maria.reyes@example.com' },
  { commuterId: 'CM-00002', fullName: 'Jose Manalo', mobileNumber: '+639181234568', email: 'jose.manalo@example.com' },
  { commuterId: 'CM-00003', fullName: 'Angelica Torres', mobileNumber: '+639181234569', email: 'angelica.torres@example.com' },
  { commuterId: 'CM-00004', fullName: 'Miguel Aquino', mobileNumber: '+639181234570', email: 'miguel.aquino@example.com' },
  { commuterId: 'CM-00005', fullName: 'Katrina Domingo', mobileNumber: '+639181234571', email: 'katrina.domingo@example.com' },
];

async function main() {
  const driverHash = await bcrypt.hash(DRIVER_PASSWORD, 10);
  const commuterHash = await bcrypt.hash(COMMUTER_PASSWORD, 10);

  for (const d of drivers) {
    const existing = await prisma.driver.findUnique({ where: { mobileNumber: d.mobileNumber } });
    if (existing) {
      console.log(`Driver ${d.mobileNumber} already seeded, skipping.`);
      continue;
    }
    await prisma.driver.create({
      data: { ...d, passwordHash: driverHash, qrToken: await generateQrToken(), licenseVerificationStatus: 'APPROVED' },
    });
    console.log(`Seeded driver ${d.fullName}: ${d.mobileNumber} / ${DRIVER_PASSWORD}`);
  }

  for (const c of commuters) {
    const existing = await prisma.commuter.findUnique({ where: { mobileNumber: c.mobileNumber } });
    if (existing) {
      console.log(`Commuter ${c.mobileNumber} already seeded, skipping.`);
      continue;
    }
    await prisma.commuter.create({
      data: { ...c, passwordHash: commuterHash, phoneVerifiedAt: new Date(), verificationStatus: 'APPROVED', isActive: true },
    });
    console.log(`Seeded commuter ${c.fullName}: ${c.mobileNumber} / ${COMMUTER_PASSWORD}`);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
