import { calculateAge, MIN_ADULT_AGE } from '../utils/date';
import { FACE_MATCH_AUTO_CLEAR_SCORE } from './faceMatch';

/**
 * Rules applied to a commuter's government ID, shared by POST
 * /signup/:ticket/id-photos, POST /signup and POST /resubmit so all three
 * enforce the same thing.
 *
 * The birth/expiry dates are read off the ID photo by the app (on-device
 * OCR) and sent alongside it — the server can't re-read the photo. So:
 *   - a date that *was* read and fails (expired, under 18) is a hard
 *     rejection, and
 *   - a date that is missing, or doesn't match the sign-up form, can never
 *     auto-approve the account — it goes to a human (see [reviewReasons]).
 * Skipping the dates in a direct API call therefore only ever means manual
 * review, never an automatic approval.
 */

export type ReviewReason =
  | 'FACE_NOT_MATCHED'
  | 'FACE_UNVERIFIED'
  | 'BIRTH_DATE_MISMATCH'
  | 'BIRTH_DATE_UNREADABLE'
  | 'EXPIRY_DATE_UNREADABLE';

/** An ID is valid through its printed expiry date, so it only counts as
 * expired the day after. Compares whole UTC days (dates are `@db.Date`). */
export function isIdExpired(expiryDate: Date, asOf: Date = new Date()): boolean {
  const startOfToday = Date.UTC(asOf.getUTCFullYear(), asOf.getUTCMonth(), asOf.getUTCDate());
  return expiryDate.getTime() < startOfToday;
}

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

/**
 * The message to reject the submission with, or null if the ID itself is
 * acceptable. Only inspects dates that were actually read.
 */
export function idRejectionMessage(input: {
  idBirthDate: Date | null;
  idExpiryDate: Date | null;
  hasExpiry: boolean;
}): string | null {
  if (input.idBirthDate && calculateAge(input.idBirthDate) < MIN_ADULT_AGE) {
    return `The birthdate on this ID shows you are under ${MIN_ADULT_AGE}. You must be ${MIN_ADULT_AGE} or older to use ManibelaApp.`;
  }
  if (input.hasExpiry && input.idExpiryDate && isIdExpired(input.idExpiryDate)) {
    return 'This ID has expired. Please use a valid, unexpired ID.';
  }
  return null;
}

/**
 * Everything that stops this submission from being auto-approved. Empty
 * means it can be approved without a human.
 */
export function reviewReasons(input: {
  /** Birth date the commuter typed on the sign-up form, if any. */
  signupBirthDate: Date | null;
  idBirthDate: Date | null;
  idExpiryDate: Date | null;
  hasExpiry: boolean;
  faceMatchScore: number | null;
}): ReviewReason[] {
  const reasons: ReviewReason[] = [];

  if (!input.idBirthDate) {
    reasons.push('BIRTH_DATE_UNREADABLE');
  } else if (input.signupBirthDate && !sameDay(input.signupBirthDate, input.idBirthDate)) {
    reasons.push('BIRTH_DATE_MISMATCH');
  }

  if (input.hasExpiry && !input.idExpiryDate) reasons.push('EXPIRY_DATE_UNREADABLE');

  if (input.faceMatchScore === null) reasons.push('FACE_UNVERIFIED');
  else if (input.faceMatchScore < FACE_MATCH_AUTO_CLEAR_SCORE) reasons.push('FACE_NOT_MATCHED');

  return reasons;
}
