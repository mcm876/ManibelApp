import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { ApiError } from '../lib/errors';
import { asyncHandler } from '../lib/asyncHandler';
import { requireAdmin } from '../middleware/requireAdmin';

export const adminIdReviewRouter = Router();
adminIdReviewRouter.use(requireAdmin);

const statusSchema = z.enum(['PENDING_REVIEW', 'APPROVED', 'REJECTED']);
const rejectSchema = z.object({ reason: z.string().trim().min(1, 'A rejection reason is required').max(500) });

const submissionInclude = {
  idType: { select: { code: true, label: true } },
  commuter: { select: { commuterId: true, fullName: true, mobileNumber: true, dateOfBirth: true } },
} as const;

/** Never expose server file paths; images are fetched through the /images route. */
function toAdminView(s: {
  id: string;
  status: string;
  reviewReasons: string[];
  birthDate: Date | null;
  expiryDate: Date | null;
  faceMatchScore: number | null;
  backPath: string | null;
  rejectionReason: string | null;
  reviewedAt: Date | null;
  createdAt: Date;
  idType: { code: string; label: string };
  commuter: { commuterId: string; fullName: string; mobileNumber: string; dateOfBirth: Date | null };
}) {
  return {
    id: s.id,
    status: s.status,
    reviewReasons: s.reviewReasons,
    idType: s.idType,
    commuter: s.commuter,
    birthDate: s.birthDate,
    expiryDate: s.expiryDate,
    faceMatchScore: s.faceMatchScore,
    hasBackImage: s.backPath !== null,
    rejectionReason: s.rejectionReason,
    reviewedAt: s.reviewedAt,
    createdAt: s.createdAt,
  };
}

// GET /admin/id-submissions?status=PENDING_REVIEW  (oldest first, so the queue is worked in order)
adminIdReviewRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const parsedStatus = statusSchema.safeParse(req.query.status ?? 'PENDING_REVIEW');
    if (!parsedStatus.success) throw new ApiError(400, 'validation_error', 'Invalid status filter');

    const submissions = await prisma.idSubmission.findMany({
      where: { status: parsedStatus.data },
      orderBy: { createdAt: 'asc' },
      include: submissionInclude,
      take: 100,
    });
    res.json({ submissions: submissions.map(toAdminView) });
  }),
);

adminIdReviewRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const submission = await prisma.idSubmission.findUnique({
      where: { id: String(req.params.id) },
      include: submissionInclude,
    });
    if (!submission) throw new ApiError(404, 'not_found', 'Submission not found');
    res.json({ submission: toAdminView(submission) });
  }),
);

// GET /admin/id-submissions/:id/images/front|back|selfie
adminIdReviewRouter.get(
  '/:id/images/:kind',
  asyncHandler(async (req, res) => {
    const kind = String(req.params.kind);
    if (kind !== 'front' && kind !== 'back' && kind !== 'selfie') {
      throw new ApiError(400, 'validation_error', 'kind must be front, back or selfie');
    }

    const submission = await prisma.idSubmission.findUnique({ where: { id: String(req.params.id) } });
    if (!submission) throw new ApiError(404, 'not_found', 'Submission not found');

    // The path always comes from the DB row, never from the request.
    const filePath = { front: submission.frontPath, back: submission.backPath, selfie: submission.selfiePath }[kind];
    if (!filePath) throw new ApiError(404, 'not_found', 'This submission has no such image');

    res.sendFile(filePath, (err) => {
      if (err && !res.headersSent) res.status(404).json({ error: 'not_found', message: 'Image file is missing' });
    });
  }),
);

adminIdReviewRouter.post(
  '/:id/approve',
  asyncHandler(async (req, res) => {
    const id = String(req.params.id);
    await prisma.$transaction(async (tx) => {
      // Guarded update: only a still-pending submission can be decided, and
      // two admins racing on the same one can't both succeed.
      const { count } = await tx.idSubmission.updateMany({
        where: { id, status: 'PENDING_REVIEW' },
        data: { status: 'APPROVED', reviewedAt: new Date(), rejectionReason: null },
      });
      if (count === 0) await throwNotDecidable(tx, id);

      const submission = await tx.idSubmission.findUniqueOrThrow({ where: { id } });
      await tx.commuter.update({
        where: { id: submission.commuterId },
        data: { idVerificationStatus: 'VERIFIED' },
      });
    });
    res.json({ status: 'APPROVED' });
  }),
);

adminIdReviewRouter.post(
  '/:id/reject',
  asyncHandler(async (req, res) => {
    const parsed = rejectSchema.safeParse(req.body);
    if (!parsed.success) throw new ApiError(400, 'validation_error', 'A rejection reason is required');

    const id = String(req.params.id);
    await prisma.$transaction(async (tx) => {
      const { count } = await tx.idSubmission.updateMany({
        where: { id, status: 'PENDING_REVIEW' },
        data: { status: 'REJECTED', reviewedAt: new Date(), rejectionReason: parsed.data.reason },
      });
      if (count === 0) await throwNotDecidable(tx, id);

      const submission = await tx.idSubmission.findUniqueOrThrow({ where: { id } });
      // Back to NONE so the commuter can submit a new ID.
      await tx.commuter.update({
        where: { id: submission.commuterId },
        data: { idVerificationStatus: 'NONE' },
      });
    });
    res.json({ status: 'REJECTED' });
  }),
);

async function throwNotDecidable(
  tx: { idSubmission: { findUnique: typeof prisma.idSubmission.findUnique } },
  id: string,
): Promise<never> {
  const existing = await tx.idSubmission.findUnique({ where: { id }, select: { status: true } });
  if (!existing) throw new ApiError(404, 'not_found', 'Submission not found');
  throw new ApiError(409, 'already_reviewed', `This submission is already ${existing.status}`);
}
