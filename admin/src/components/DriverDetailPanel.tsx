import { useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { ConfirmDialog } from './ConfirmDialog';
import { apiClient, ApiError } from '../lib/apiClient';
import { formatManilaDate } from '../lib/formatDate';
import { formatPhone } from '../lib/formatPhone';
import { usePolling } from '../lib/usePolling';
import { DriverTripHistorySection } from './DriverTripHistorySection';
import { FaceMatchCard } from './FaceMatchCard';
import { PhotoAccessLogNote, type PhotoAccessLogEntry } from './PhotoAccessLogNote';
import { VerificationBadge, type VerificationStatus } from './VerificationBadge';

interface DriverDetail {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  licenseFrontUrl: string | null;
  licenseBackUrl: string | null;
  selfieUrl: string | null;
  faceMatchScore: number | null;
  licenseNumber: string | null;
  licenseVerificationStatus: VerificationStatus;
  qrToken: string | null;
  isActive: boolean;
  reportCount: number;
  /** This driver's live average across every commuter rating they've
   * received (see Rating's doc comment in schema.prisma) — null until
   * they have at least one. */
  averageRating: number | null;
  ratingCount: number;
  createdAt: string;
  photoAccessLog: PhotoAccessLogEntry[];
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

function EditIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
  );
}

/** One side of the license. Click opens the full-size image in a new tab
 * so small print (number, expiry) can be read properly. */
function LicensePhotoView({ label, url }: { label: string; url: string | null }) {
  const resolved = apiClient.resolveUrl(url);
  return (
    <div>
      <p className="mb-1.5 text-xs font-semibold text-gray-600">{label}</p>
      <div className="flex aspect-video items-center justify-center overflow-hidden rounded-lg border border-gray-200 bg-gray-50">
        {resolved ? (
          <a href={resolved} target="_blank" rel="noreferrer" title="Open full size" className="block h-full w-full">
            <img src={resolved} alt={label} className="h-full w-full object-contain" />
          </a>
        ) : (
          <span className="text-xs text-gray-400">Not uploaded</span>
        )}
      </div>
    </div>
  );
}

const LICENSE_ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const LICENSE_MAX_BYTES = 5 * 1024 * 1024;

/** Admin-side upload/replace of the license front and back. Either side
 * can be sent alone to replace just that one. A fresh upload resets the
 * status to Pending (server-side), so it has to be reviewed again. */
function LicenseUploadControls({
  driverId,
  hasLicense,
  onUploaded,
  onDeleteClick,
}: {
  driverId: string;
  hasLicense: boolean;
  onUploaded: (change: Partial<DriverDetail>) => void;
  onDeleteClick: () => void;
}) {
  const [front, setFront] = useState<File | null>(null);
  const [back, setBack] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [inputKey, setInputKey] = useState(0);

  function pick(side: 'front' | 'back', file: File | null) {
    setError(null);
    if (file && !LICENSE_ALLOWED_TYPES.includes(file.type)) {
      setError('Only JPEG, PNG or WEBP images are allowed.');
      return;
    }
    if (file && file.size > LICENSE_MAX_BYTES) {
      setError('Each image must be 5 MB or smaller.');
      return;
    }
    (side === 'front' ? setFront : setBack)(file);
  }

  async function handleUpload() {
    if ((!front && !back) || isUploading) return;
    setIsUploading(true);
    setError(null);
    try {
      const files: Record<string, File> = {};
      if (front) files.licenseFront = front;
      if (back) files.licenseBack = back;
      const res = await apiClient.uploadFiles<{ driver: Partial<DriverDetail> }>(
        `/api/admin/drivers/${driverId}/license-photos`,
        files,
      );
      onUploaded(res.driver);
      setFront(null);
      setBack(null);
      setInputKey((k) => k + 1);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Upload failed.');
    } finally {
      setIsUploading(false);
    }
  }

  const fileInputClass =
    'block w-full text-xs text-gray-600 file:mr-2 file:rounded-lg file:border-0 file:bg-gray-100 file:px-2.5 file:py-1.5 file:text-xs file:font-semibold file:text-gray-700 hover:file:bg-gray-200';

  return (
    <div className="mt-3 rounded-xl border border-border-subtle p-3">
      <p className="text-xs font-semibold text-gray-600">{hasLicense ? 'Replace license photos' : 'Upload license photos'}</p>
      <div className="mt-2 grid grid-cols-2 gap-3" key={inputKey}>
        <label className="block text-xs text-gray-500">
          Front
          <input type="file" accept="image/jpeg,image/png,image/webp" className={fileInputClass} onChange={(e) => pick('front', e.target.files?.[0] ?? null)} />
        </label>
        <label className="block text-xs text-gray-500">
          Back
          <input type="file" accept="image/jpeg,image/png,image/webp" className={fileInputClass} onChange={(e) => pick('back', e.target.files?.[0] ?? null)} />
        </label>
      </div>
      {error && <p className="mt-1.5 text-xs font-medium text-brand-red">{error}</p>}
      <div className="mt-2.5 flex items-center justify-between gap-2">
        <button
          onClick={handleUpload}
          disabled={isUploading || (!front && !back)}
          className="rounded-lg bg-brand-blue px-3 py-1.5 text-xs font-semibold text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {isUploading ? 'Uploading...' : hasLicense ? 'Replace' : 'Upload'}
        </button>
        {hasLicense && (
          <button
            onClick={onDeleteClick}
            disabled={isUploading}
            className="rounded-lg border border-status-critical px-3 py-1.5 text-xs font-semibold text-status-critical hover:bg-status-critical-bg disabled:opacity-50"
          >
            Delete photos
          </button>
        )}
      </div>
      <p className="mt-1.5 text-[11px] text-gray-400">JPEG, PNG or WEBP, up to 5 MB each. A new upload sets the status back to Pending.</p>
    </div>
  );
}

// The latest birth date that still makes someone 18 today — mirrors
// DriversPage's own AddDriverModal constant. Matches MIN_ADULT_AGE,
// enforced server-side too (PATCH /admin/drivers/:id/date-of-birth)
// since this max attribute alone doesn't stop a direct API call.
const maxDateOfBirthForAge18 = (() => {
  const d = new Date();
  d.setFullYear(d.getFullYear() - 18);
  return d.toISOString().slice(0, 10);
})();

/** Date of birth is no longer editable by the driver themselves (see
 * PATCH /driver/me) — only an admin can set/correct it, same
 * verified-by-a-human reasoning as plate/license number. Uses a native
 * `<input type="date">`, whose value format ("YYYY-MM-DD") already
 * matches what the backend's `dateOnly` schema expects/returns. */
function DateOfBirthField({
  driverId,
  dateOfBirth,
  onChanged,
}: {
  driverId: string;
  dateOfBirth: string | null;
  onChanged: (dateOfBirth: string | null) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(dateOfBirth ?? '');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function startEditing() {
    setValue(dateOfBirth ?? '');
    setError(null);
    setIsEditing(true);
  }

  async function handleSave() {
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.patch<{ driver: { dateOfBirth: string | null } }>(
        `/api/admin/drivers/${driverId}/date-of-birth`,
        { dateOfBirth: value || null },
      );
      onChanged(res.driver.dateOfBirth);
      setIsEditing(false);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  if (!isEditing) {
    return (
      <div className="flex justify-between">
        <dt className="text-gray-500">Date of Birth</dt>
        <dd className="flex items-center gap-1.5 font-medium text-gray-900">
          {dateOfBirth ?? '—'}
          <button
            onClick={startEditing}
            className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-brand-blue"
            aria-label="Edit date of birth"
          >
            <EditIcon />
          </button>
        </dd>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <dt className="text-gray-500">Date of Birth</dt>
        <div className="flex items-center gap-1.5">
          <input
            autoFocus
            type="date"
            max={maxDateOfBirthForAge18}
            title="Drivers must be at least 18 years old"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            className="rounded-lg border border-border-subtle px-2 py-1 text-sm font-medium focus:border-brand-blue focus:outline-none"
          />
          <button
            onClick={handleSave}
            disabled={isSubmitting}
            className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:opacity-60"
          >
            {isSubmitting ? '...' : 'Save'}
          </button>
          <button
            onClick={() => setIsEditing(false)}
            disabled={isSubmitting}
            className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </div>
      {error && <p className="text-right text-xs font-medium text-brand-red">{error}</p>}
    </div>
  );
}

/** Editable independently of the photo-review flow below (Approve/Reject
 * on a submitted photo also sets this, but an admin can correct it here
 * any time — e.g. fixing a typo from Add Driver, or before any photo's
 * even been submitted). Doesn't touch licenseVerificationStatus — see
 * PATCH /admin/drivers/:id/license-number's own doc comment for how it
 * tells the two kinds of update apart. */
function LicenseNumberField({
  driverId,
  licenseNumber,
  onChanged,
}: {
  driverId: string;
  licenseNumber: string | null;
  onChanged: (licenseNumber: string | null) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(licenseNumber ?? '');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function startEditing() {
    setValue(licenseNumber ?? '');
    setError(null);
    setIsEditing(true);
  }

  async function handleSave() {
    if (isSubmitting) return;
    if (!value.trim()) {
      setError('License number is required.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.patch<{ driver: { licenseNumber: string | null } }>(
        `/api/admin/drivers/${driverId}/license-number`,
        { licenseNumber: value.trim() },
      );
      onChanged(res.driver.licenseNumber);
      setIsEditing(false);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  if (!isEditing) {
    return (
      <div className="flex justify-between">
        <dt className="text-gray-500">License Number</dt>
        <dd className="flex items-center gap-1.5 font-medium text-gray-900">
          {licenseNumber ?? '—'}
          <button
            onClick={startEditing}
            className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-brand-blue"
            aria-label="Edit license number"
          >
            <EditIcon />
          </button>
        </dd>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <dt className="text-gray-500">License Number</dt>
        <div className="flex items-center gap-1.5">
          <input
            autoFocus
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="N01-23-456789"
            className="w-36 rounded-lg border border-border-subtle px-2 py-1 text-right text-sm font-medium focus:border-brand-blue focus:outline-none"
          />
          <button
            onClick={handleSave}
            disabled={isSubmitting}
            className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:opacity-60"
          >
            {isSubmitting ? '...' : 'Save'}
          </button>
          <button
            onClick={() => setIsEditing(false)}
            disabled={isSubmitting}
            className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </div>
      {error && <p className="text-right text-xs font-medium text-brand-red">{error}</p>}
    </div>
  );
}

function PlateNumberField({
  driverId,
  plateNumber,
  onChanged,
}: {
  driverId: string;
  plateNumber: string;
  onChanged: (plateNumber: string) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(plateNumber);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function startEditing() {
    setValue(plateNumber);
    setError(null);
    setIsEditing(true);
  }

  async function handleSave() {
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.patch<{ driver: { plateNumber: string } }>(
        `/api/admin/drivers/${driverId}/plate-number`,
        { plateNumber: value },
      );
      onChanged(res.driver.plateNumber);
      setIsEditing(false);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  if (!isEditing) {
    return (
      <div className="flex justify-between">
        <dt className="text-gray-500">Plate Number</dt>
        <dd className="flex items-center gap-1.5 font-medium text-gray-900">
          {plateNumber}
          <button
            onClick={startEditing}
            className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-brand-blue"
            aria-label="Edit plate number"
          >
            <EditIcon />
          </button>
        </dd>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <dt className="text-gray-500">Plate Number</dt>
        <div className="flex items-center gap-1.5">
          <input
            autoFocus
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="ABC123"
            className="w-28 rounded-lg border border-border-subtle px-2 py-1 text-right text-sm font-medium uppercase focus:border-brand-blue focus:outline-none"
          />
          <button
            onClick={handleSave}
            disabled={isSubmitting}
            className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:opacity-60"
          >
            {isSubmitting ? '...' : 'Save'}
          </button>
          <button
            onClick={() => setIsEditing(false)}
            disabled={isSubmitting}
            className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </div>
      {error && <p className="text-right text-xs font-medium text-brand-red">{error}</p>}
    </div>
  );
}

export function DriverDetailPanel({
  driverId,
  onClose,
  onStatusChange,
  onDeleted,
}: {
  driverId: string;
  onClose: () => void;
  onStatusChange: (isActive: boolean) => void;
  onDeleted: () => void;
}) {
  const [driver, setDriver] = useState<DriverDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [confirmingLicenseDelete, setConfirmingLicenseDelete] = useState(false);
  const [licenseNumberInput, setLicenseNumberInput] = useState('');
  const [licenseActionError, setLicenseActionError] = useState<string | null>(null);
  const [isSubmittingLicense, setIsSubmittingLicense] = useState(false);

  // Bumped by every successful edit made from this panel. A poll (below)
  // that was already in flight when an edit was saved carries a snapshot
  // from *before* that edit — applying it would flip the field back to the
  // old value until the next poll, so its response is dropped instead.
  const localChangeVersion = useRef(0);

  // Whether the admin has typed into the license-review box themselves —
  // while they haven't, it simply mirrors whatever number is on file (so it
  // can't go stale after the number is edited elsewhere in this panel, or
  // by another admin); once they have, it's theirs and never overwritten.
  const licenseInputTouched = useRef(false);

  function fetchDriver() {
    const versionAtRequest = localChangeVersion.current;
    apiClient
      .get<{ driver: DriverDetail }>(`/api/admin/drivers/${driverId}`)
      .then((res) => {
        if (versionAtRequest !== localChangeVersion.current) return;
        setDriver(res.driver);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load this driver.'));
  }

  /** Applies a server-confirmed change to what's shown right now, without
   * waiting for (or being undone by) the next poll. Merges into the latest
   * state rather than a render-time snapshot so two quick edits can't
   * overwrite each other. */
  function applyLocalChange(change: Partial<DriverDetail>) {
    localChangeVersion.current += 1;
    setDriver((current) => (current ? { ...current, ...change } : current));
  }

  useEffect(() => {
    setDriver(null);
    licenseInputTouched.current = false;
    fetchDriver();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driverId]);

  // Keeps the review input showing the number on file (e.g. re-reviewing
  // after a rejection, or right after the number above was just edited)
  // until the admin starts typing in it themselves.
  const licenseNumberOnFile = driver?.licenseNumber ?? '';
  useEffect(() => {
    if (!licenseInputTouched.current) setLicenseNumberInput(licenseNumberOnFile);
  }, [driverId, licenseNumberOnFile]);

  // Keeps this panel current while it's open — a driver submitting an
  // explanation, or another admin reviewing a trip, should show up here
  // without having to close and reopen the panel.
  usePolling(fetchDriver, 8000);

  async function handleDeleteLicense() {
    if (!driver || isSubmitting) return;
    setIsSubmitting(true);
    try {
      const res = await apiClient.delete<{ driver: Partial<DriverDetail> }>(`/api/admin/drivers/${driver.id}/license-photos`);
      applyLocalChange(res.driver);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
      setConfirmingLicenseDelete(false);
    }
  }

  async function handleDelete() {
    if (!driver || isSubmitting) return;
    setIsSubmitting(true);
    try {
      await apiClient.delete(`/api/admin/drivers/${driver.id}`);
      onDeleted();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
      setConfirmingDelete(false);
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleToggleStatus() {
    if (!driver || isSubmitting) return;
    setIsSubmitting(true);
    try {
      const nextActive = !driver.isActive;
      await apiClient.patch(`/api/admin/drivers/${driver.id}/status`, { isActive: nextActive });
      applyLocalChange({ isActive: nextActive });
      onStatusChange(nextActive);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  // The admin types the number in themselves after looking at the
  // submitted photo — no OCR/auto-detect (see TODO.md).
  async function handleLicenseReview(status: 'APPROVED' | 'REJECTED') {
    if (!driver || isSubmittingLicense) return;
    if (status === 'APPROVED' && !licenseNumberInput.trim()) {
      setLicenseActionError('Enter the license number before approving.');
      return;
    }
    setLicenseActionError(null);
    setIsSubmittingLicense(true);
    try {
      const res = await apiClient.patch<{ driver: { licenseNumber: string | null; licenseVerificationStatus: VerificationStatus } }>(
        `/api/admin/drivers/${driver.id}/license-number`,
        { status, licenseNumber: licenseNumberInput.trim() || undefined },
      );
      applyLocalChange({
        licenseNumber: res.driver.licenseNumber,
        licenseVerificationStatus: res.driver.licenseVerificationStatus,
      });
      // The number on file is now what the server just confirmed — drop
      // any hand-typed draft so the box reflects it.
      licenseInputTouched.current = false;
      setLicenseNumberInput(res.driver.licenseNumber ?? '');
    } catch (err) {
      setLicenseActionError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmittingLicense(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">Driver Details</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}

        {!driver && !error && <p className="p-5 text-sm text-gray-500">Loading...</p>}

        {driver && (
          <div className="flex flex-1 flex-col gap-6 p-5">
            <div className="flex items-center gap-4">
              <div className="h-16 w-16 shrink-0 overflow-hidden rounded-full bg-gray-200">
                {driver.photoUrl && (
                  <img src={apiClient.resolveUrl(driver.photoUrl) ?? undefined} alt="" className="h-full w-full object-cover" />
                )}
              </div>
              <div>
                <p className="font-semibold text-gray-900">{driver.fullName}</p>
                <p className="text-xs text-gray-500">{formatPhone(driver.mobileNumber)}</p>
                <span
                  className={`mt-1 inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                    driver.isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
                  }`}
                >
                  {driver.isActive ? 'Active' : 'Inactive'}
                </span>
              </div>
            </div>

            <div className="flex items-center justify-between rounded-xl border border-border-subtle p-4">
              <div className="flex gap-6">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Rating</p>
                  <p className="mt-1 flex items-baseline gap-1 font-display text-2xl font-semibold text-gray-900">
                    {driver.averageRating != null ? driver.averageRating.toFixed(1) : '—'}
                    {driver.averageRating != null && <span className="text-sm font-medium text-gray-400">/5</span>}
                  </p>
                  <p className="text-xs text-gray-400">
                    {driver.ratingCount > 0 ? `${driver.ratingCount} rating${driver.ratingCount === 1 ? '' : 's'}` : 'No ratings yet'}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Report Count</p>
                  <p className="mt-1 font-display text-2xl font-semibold text-gray-900">{driver.reportCount}</p>
                </div>
              </div>
              {driver.qrToken && (
                <div className="rounded-lg border border-border-subtle bg-white p-2">
                  <QRCodeSVG value={`MNBL-DRV:${driver.qrToken}`} size={72} />
                </div>
              )}
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Driver Information</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Driver ID</dt>
                  <dd className="font-medium text-gray-900">{driver.driverId}</dd>
                </div>
                <PlateNumberField
                  driverId={driver.id}
                  plateNumber={driver.plateNumber}
                  onChanged={(plateNumber) => applyLocalChange({ plateNumber })}
                />
                <LicenseNumberField
                  driverId={driver.id}
                  licenseNumber={driver.licenseNumber}
                  onChanged={(licenseNumber) => applyLocalChange({ licenseNumber })}
                />
                <DateOfBirthField
                  driverId={driver.id}
                  dateOfBirth={driver.dateOfBirth}
                  onChanged={(dateOfBirth) => applyLocalChange({ dateOfBirth })}
                />
                <div className="flex justify-between">
                  <dt className="text-gray-500">Date Registered</dt>
                  <dd className="font-medium text-gray-900">{formatManilaDate(driver.createdAt)}</dd>
                </div>
              </dl>
            </div>

            <div>
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">License Photos</h3>
                <VerificationBadge status={driver.licenseVerificationStatus} notSubmitted={!driver.licenseFrontUrl} approvedLabel="Verified" />
              </div>
              {driver.selfieUrl && <FaceMatchCard score={driver.faceMatchScore} documentLabel="License Front" />}
              <div className="mt-3 grid grid-cols-2 gap-3">
                <LicensePhotoView label="License Front" url={driver.licenseFrontUrl} />
                <LicensePhotoView label="License Back" url={driver.licenseBackUrl} />
                {driver.selfieUrl && <LicensePhotoView label="Selfie (from driver app)" url={driver.selfieUrl} />}
              </div>
              <LicenseUploadControls
                driverId={driver.id}
                hasLicense={Boolean(driver.licenseFrontUrl || driver.licenseBackUrl || driver.selfieUrl)}
                onUploaded={applyLocalChange}
                onDeleteClick={() => setConfirmingLicenseDelete(true)}
              />
              <PhotoAccessLogNote entries={driver.photoAccessLog} />

              {driver.licenseFrontUrl && (
                <div className="mt-3">
                  <p className="mb-1.5 text-xs font-semibold text-gray-600">License Number</p>
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      value={licenseNumberInput}
                      onChange={(e) => {
                        licenseInputTouched.current = true;
                        setLicenseNumberInput(e.target.value);
                      }}
                      placeholder="Type the number from the photo"
                      className="flex-1 rounded-lg border border-gray-200 px-2.5 py-1.5 text-sm focus:border-brand-blue focus:outline-none"
                    />
                    <button
                      onClick={() => handleLicenseReview('REJECTED')}
                      disabled={isSubmittingLicense || driver.licenseVerificationStatus === 'REJECTED'}
                      className="rounded-lg border border-status-critical px-2.5 py-1 text-xs font-semibold text-status-critical hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Reject
                    </button>
                    <button
                      onClick={() => handleLicenseReview('APPROVED')}
                      disabled={isSubmittingLicense || driver.licenseVerificationStatus === 'APPROVED'}
                      className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Verify
                    </button>
                  </div>
                  {licenseActionError && <p className="mt-1.5 text-xs font-medium text-brand-red">{licenseActionError}</p>}
                </div>
              )}
            </div>

            <DriverTripHistorySection driverId={driver.id} driverName={driver.fullName} plateNumber={driver.plateNumber} />

            <button
              onClick={handleToggleStatus}
              disabled={isSubmitting}
              className={`mt-auto w-full rounded-lg py-2.5 text-sm font-semibold transition disabled:opacity-60 ${
                driver.isActive
                  ? 'border border-status-critical text-status-critical hover:bg-status-critical-bg'
                  : 'bg-brand-blue text-white hover:brightness-110'
              }`}
            >
              {isSubmitting ? 'Please wait...' : driver.isActive ? 'Deactivate Driver' : 'Reactivate Driver'}
            </button>
            <button
              onClick={() => setConfirmingDelete(true)}
              disabled={isSubmitting}
              className="w-full rounded-lg bg-brand-red py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
            >
              Delete Driver
            </button>
          </div>
        )}
      </div>
      {confirmingLicenseDelete && driver && (
        <ConfirmDialog
          icon={<svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6" /></svg>}
          tone="danger"
          title="Delete license photos?"
          message="This removes the license front and back (and any selfie) and clears the status. The driver won't be able to start trips until a license is verified again."
          confirmLabel="Delete"
          isSubmitting={isSubmitting}
          onConfirm={handleDeleteLicense}
          onCancel={() => setConfirmingLicenseDelete(false)}
        />
      )}
      {confirmingDelete && driver && (
        <ConfirmDialog
          icon={<svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6M10 11v6M14 11v6" /></svg>}
          tone="danger"
          title="Delete this driver?"
          message="This permanently deletes the account along with their trips, ratings, complaints and notifications. This cannot be undone."
          confirmLabel="Delete"
          isSubmitting={isSubmitting}
          onConfirm={handleDelete}
          onCancel={() => setConfirmingDelete(false)}
        />
      )}
    </div>
  );
}
