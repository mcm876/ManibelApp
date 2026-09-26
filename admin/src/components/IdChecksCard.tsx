// Mirrors the ReviewReason codes in backend/src/lib/idChecks.ts. Worded for
// the reviewer (what to look at), not the commuter.
const REASON_TEXT: Record<string, string> = {
  FACE_NOT_MATCHED: 'Selfie did not match the ID photo — compare the photos below.',
  FACE_UNVERIFIED: 'No face could be confidently compared — compare the photos below yourself.',
  BIRTH_DATE_MISMATCH: "Birthdate on the ID differs from the one entered at sign-up.",
  BIRTH_DATE_UNREADABLE: "The birthdate couldn't be read off the ID — check it in the photo.",
  EXPIRY_DATE_UNREADABLE: "The expiry date couldn't be read off the ID — check it in the photo.",
};

/** Today's date in Manila as YYYY-MM-DD (dates here are plain calendar
 * dates, so compare as strings — no timezone math). */
function todayInManila(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Manila' });
}

function ageOn(birthDate: string, today: string): number {
  const [by, bm, bd] = birthDate.split('-').map(Number);
  const [ty, tm, td] = today.split('-').map(Number);
  let age = ty - by;
  if (tm < bm || (tm === bm && td < bd)) age -= 1;
  return age;
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-3 text-xs">
      <dt className="text-gray-500">{label}</dt>
      <dd className="text-right font-medium text-gray-900">{children}</dd>
    </div>
  );
}

function Flag({ tone, children }: { tone: 'good' | 'warning' | 'critical'; children: React.ReactNode }) {
  const cls = {
    good: 'bg-status-good-bg text-status-good',
    warning: 'bg-status-warning-bg text-status-warning',
    critical: 'bg-status-critical-bg text-status-critical',
  }[tone];
  return <span className={`ml-1.5 inline-block rounded-full px-2 py-0.5 text-[10.5px] font-semibold ${cls}`}>{children}</span>;
}

/** The dates the app read off a commuter's ID and why (if at all) the
 * account was held for manual review — shown next to the face-match card
 * so the reviewer sees everything the automated checks decided on. */
export function IdChecksCard({
  idBirthDate,
  idExpiryDate,
  signupBirthDate,
  reviewReasons,
}: {
  idBirthDate: string | null;
  idExpiryDate: string | null;
  signupBirthDate: string | null;
  reviewReasons: string[];
}) {
  // Accounts submitted before the ID date checks existed have no dates and
  // no reasons — say so instead of implying the ID was checked and clean.
  const legacy = idBirthDate === null && idExpiryDate === null && reviewReasons.length === 0;
  if (legacy) {
    return (
      <div className="mt-2.5 rounded-[10px] border border-gray-200 bg-gray-50 px-3.5 py-3">
        <p className="text-[10.5px] font-semibold uppercase tracking-wide text-gray-400">ID Checks</p>
        <p className="mt-1 text-xs text-gray-500">
          Not checked — this ID was submitted before birthdate and expiry checks were added. Verify the dates in the
          photos below.
        </p>
      </div>
    );
  }

  const today = todayInManila();
  const age = idBirthDate ? ageOn(idBirthDate, today) : null;
  const mismatch = idBirthDate !== null && signupBirthDate !== null && idBirthDate !== signupBirthDate;
  const expired = idExpiryDate !== null && idExpiryDate < today;
  const needsReview = reviewReasons.length > 0;

  const tone = needsReview
    ? { border: 'border-[#f3d9b1]', bg: 'bg-status-warning-bg', text: 'text-status-warning' }
    : { border: 'border-[#bfe8bf]', bg: 'bg-status-good-bg', text: 'text-status-good' };

  return (
    <div className={`mt-2.5 rounded-[10px] border ${tone.border} ${tone.bg} px-3.5 py-3`}>
      <p className={`text-[10.5px] font-semibold uppercase tracking-wide ${tone.text}`}>ID Checks</p>

      <dl className="mt-2 space-y-1.5">
        <Row label="Birthdate on ID">
          {idBirthDate ?? 'Not read'}
          {age !== null && <Flag tone={age >= 18 ? 'good' : 'critical'}>{age >= 18 ? `${age} yrs` : `${age} yrs · under 18`}</Flag>}
          {mismatch && <Flag tone="warning">differs from sign-up ({signupBirthDate})</Flag>}
        </Row>
        <Row label="Expiry on ID">
          {idExpiryDate ?? (reviewReasons.includes('EXPIRY_DATE_UNREADABLE') ? 'Not read' : 'None on this ID')}
          {idExpiryDate !== null && <Flag tone={expired ? 'critical' : 'good'}>{expired ? 'Expired' : 'Valid'}</Flag>}
        </Row>
      </dl>

      {needsReview ? (
        <div className="mt-2.5 border-t border-[#f3d9b1] pt-2">
          <p className="text-[11px] font-semibold text-status-warning">Held for manual review because:</p>
          <ul className="mt-1 list-disc space-y-0.5 pl-4 text-[11px] text-[#92651f]">
            {reviewReasons.map((code) => (
              <li key={code}>{REASON_TEXT[code] ?? code}</li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="mt-2 text-[11px] text-[#3f7d3f]">Birthdate, expiry and face match all passed — no review needed.</p>
      )}
    </div>
  );
}
