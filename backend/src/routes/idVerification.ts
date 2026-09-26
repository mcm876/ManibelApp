import fs from 'node:fs';
import path from 'node:path';
import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { ApiError } from '../lib/errors';
import { asyncHandler } from '../lib/asyncHandler';
import { requireAuth } from '../middleware/requireAuth';
import { ageOn, isExpired, MIN_AGE, parseIsoDate, sameDay } from '../lib/idChecks';
import { compareFaces, FACE_MATCH_THRESHOLD } from '../lib/faceMatch';

const UPLOAD_DIR = path.resolve(__dirname, '../../uploads/id-submissions');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: UPLOAD_DIR,
    filename: (_req, file, cb) =>
      cb(null, `${Date.now()}-${Math.random().toString(36).slice(2)}${path.extname(file.originalname) || '.jpg'}`),
  }),
  limits: { fileSize: 8 * 1024 * 1024, files: 3 },
  fileFilter: (_req, file, cb) =>
    cb(null, file.mimetype.startsWith('image/') || file.mimetype === 'application/octet-stream'),
});

const bodySchema = z.object({
  idTypeCode: z.string().min(1),
  // Read from the ID photo by the app's OCR; empty when it couldn't be read.
  birthDate: z.string().optional(),
  expiryDate: z.string().optional(),
});

export const idVerificationRouter = Router();

idVerificationRouter.get(
  '/id-types',
  requireAuth('commuter'),
  asyncHandler(async (_req, res) => {
    const idTypes = await prisma.governmentIdType.findMany({
      where: { active: true },
      orderBy: [{ sortOrder: 'asc' }, { label: 'asc' }],
      select: { code: true, label: true, hasExpiry: true, requiresBack: true },
    });
    res.json({ idTypes });
  }),
);

// Where the commuter's latest ID submission stands. The app calls this from
// the "under review" screen; rejectionReason is only set when an admin has
// rejected the latest submission.
idVerificationRouter.get(
  '/id-status',
  requireAuth('commuter'),
  asyncHandler(async (req, res) => {
    const commuter = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
    if (!commuter) throw new ApiError(404, 'not_found', 'Account no longer exists');

    const latest = await prisma.idSubmission.findFirst({
      where: { commuterId: commuter.id },
      orderBy: { createdAt: 'desc' },
      include: { idType: { select: { label: true } } },
    });

    res.json({
      status: commuter.idVerificationStatus,
      idTypeLabel: latest?.idType.label ?? null,
      rejectionReason: latest?.status === 'REJECTED' ? latest.rejectionReason : null,
    });
  }),
);

idVerificationRouter.post(
  '/verify-id',
  requireAuth('commuter'),
  upload.fields([
    { name: 'front', maxCount: 1 },
    { name: 'back', maxCount: 1 },
    { name: 'selfie', maxCount: 1 },
  ]),
  asyncHandler(async (req, res) => {
    const files = (req.files ?? {}) as Record<string, Express.Multer.File[]>;
    const uploaded = Object.values(files).flat();
    const discard = () => uploaded.forEach((f) => fs.promises.unlink(f.path).catch(() => {}));

    try {
      const parsed = bodySchema.safeParse(req.body);
      if (!parsed.success) throw new ApiError(400, 'validation_error', 'idTypeCode is required');
      const { idTypeCode } = parsed.data;

      const idType = await prisma.governmentIdType.findUnique({ where: { code: idTypeCode } });
      if (!idType || !idType.active) throw new ApiError(400, 'invalid_id_type', 'That ID type is not accepted');

      const front = files.front?.[0];
      const back = files.back?.[0];
      const selfie = files.selfie?.[0];
      if (!front) throw new ApiError(400, 'missing_front', 'Upload the front of your ID');
      if (idType.requiresBack && !back) throw new ApiError(400, 'missing_back', 'Upload the back of your ID');
      if (!selfie) throw new ApiError(400, 'missing_selfie', 'Take a selfie for face verification');

      const commuter = await prisma.commuter.findUnique({ where: { id: req.auth!.sub } });
      if (!commuter) throw new ApiError(404, 'not_found', 'Account no longer exists');

      const today = new Date();
      const birthDate = parseIsoDate(parsed.data.birthDate);
      const expiryDate = parseIsoDate(parsed.data.expiryDate);

      // Hard failures: the ID itself shows the commuter can't be approved.
      if (birthDate && ageOn(birthDate, today) < MIN_AGE) {
        throw new ApiError(422, 'underage', `You must be ${MIN_AGE} or older to use ManibelApp`);
      }
      if (idType.hasExpiry && expiryDate && isExpired(expiryDate, today)) {
        throw new ApiError(422, 'id_expired', 'This ID has expired. Please use a valid, unexpired ID.');
      }

      // Soft failures: can't be auto-approved, so a person checks it.
      const reviewReasons: string[] = [];
      if (!birthDate) reviewReasons.push('BIRTH_DATE_UNREADABLE');
      else if (commuter.dateOfBirth && !sameDay(commuter.dateOfBirth, birthDate)) {
        reviewReasons.push('BIRTH_DATE_MISMATCH');
      }
      if (idType.hasExpiry && !expiryDate) reviewReasons.push('EXPIRY_DATE_UNREADABLE');

      const faceMatchScore = await compareFaces(front.path, selfie.path);
      if (faceMatchScore === null) reviewReasons.push('FACE_UNVERIFIED');
      else if (faceMatchScore < FACE_MATCH_THRESHOLD) reviewReasons.push('FACE_NOT_MATCHED');

      const status = reviewReasons.length === 0 ? 'APPROVED' : 'PENDING_REVIEW';

      await prisma.$transaction([
        prisma.idSubmission.create({
          data: {
            commuterId: commuter.id,
            idTypeId: idType.id,
            birthDate,
            expiryDate,
            faceMatchScore,
            status,
            reviewReasons,
            frontPath: front.path,
            backPath: back?.path,
            selfiePath: selfie.path,
          },
        }),
        prisma.commuter.update({
          where: { id: commuter.id },
          data: { idVerificationStatus: status === 'APPROVED' ? 'VERIFIED' : 'PENDING_REVIEW' },
        }),
      ]);

      res.status(201).json({ status, reviewReasons });
    } catch (err) {
      discard();
      throw err;
    }
  }),
);
