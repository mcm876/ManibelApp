import { useEffect, useState } from 'react';
import { apiClient, ApiError } from '../lib/apiClient';
import { formatManilaDateTime } from '../lib/formatDate';
import { COMPLAINT_STATUS_LABELS, ComplaintStatusBadge, type ComplaintStatus } from './ComplaintStatusBadge';

interface ComplaintDetail {
  id: string;
  complainantName: string;
  complainantMobileNumber: string | null;
  complainantEmail: string | null;
  driverName: string;
  plateNumber: string;
  complaintType: string;
  description: string;
  attachmentUrl: string | null;
  status: ComplaintStatus;
  investigationNotes: string | null;
  actionTaken: string | null;
  sanction: string | null;
  resolution: string | null;
  reviewedAt: string | null;
  createdAt: string;
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

export function ComplaintDetailPanel({
  complaintId,
  onClose,
  onStatusChange,
}: {
  complaintId: string;
  onClose: () => void;
  onStatusChange: (status: ComplaintStatus) => void;
}) {
  const [complaint, setComplaint] = useState<ComplaintDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  // The review record — what was looked into, what was done, any sanction an
  // authorized person approved, and how it ended. Saved together with the status.
  const [investigationNotes, setInvestigationNotes] = useState('');
  const [actionTaken, setActionTaken] = useState('');
  const [sanction, setSanction] = useState('');
  const [resolution, setResolution] = useState('');

  useEffect(() => {
    setComplaint(null);
    apiClient
      .get<{ complaint: ComplaintDetail }>(`/api/admin/complaints/${complaintId}`)
      .then((res) => {
        setComplaint(res.complaint);
        setInvestigationNotes(res.complaint.investigationNotes ?? '');
        setActionTaken(res.complaint.actionTaken ?? '');
        setSanction(res.complaint.sanction ?? '');
        setResolution(res.complaint.resolution ?? '');
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load this complaint.'));
  }, [complaintId]);

  async function handleSetStatus(status: 'INVESTIGATING' | 'RESOLVED' | 'REJECTED') {
    if (!complaint || isSubmitting) return;
    if (status === 'RESOLVED' && !resolution.trim()) {
      setError('Please record how this was resolved first.');
      return;
    }
    if (status === 'REJECTED' && !resolution.trim() && !investigationNotes.trim()) {
      setError('Please record why this complaint is being dismissed first.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.patch(`/api/admin/complaints/${complaint.id}/status`, {
        status,
        investigationNotes,
        actionTaken,
        sanction,
        resolution,
      });
      setComplaint({ ...complaint, status });
      onStatusChange(status);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  const resolvedAttachment = complaint ? apiClient.resolveUrl(complaint.attachmentUrl) : null;

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">Complaint Details</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}

        {!complaint && !error && <p className="p-5 text-sm text-gray-500">Loading...</p>}

        {complaint && (
          <div className="flex flex-1 flex-col gap-6 p-5">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-semibold text-gray-900">{complaint.complaintType}</p>
                <p className="text-xs text-gray-500">{formatManilaDateTime(complaint.createdAt)}</p>
              </div>
              <ComplaintStatusBadge status={complaint.status} />
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Description</h3>
              <p className="mt-2 text-sm text-gray-800">{complaint.description}</p>
            </div>

            {resolvedAttachment && (
              <div>
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Attachment</h3>
                <div className="mt-2 overflow-hidden rounded-xl border border-border-subtle">
                  <img src={resolvedAttachment} alt="Complaint attachment" className="w-full object-cover" />
                </div>
              </div>
            )}

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Complainant</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Name</dt>
                  <dd className="font-medium text-gray-900">{complaint.complainantName}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Mobile Number</dt>
                  <dd className="font-medium text-gray-900">{complaint.complainantMobileNumber ?? '—'}</dd>
                </div>
                <div className="flex justify-between gap-4">
                  <dt className="text-gray-500">Email</dt>
                  <dd className="min-w-0 break-all text-right font-medium text-gray-900">
                    {complaint.complainantEmail ? (
                      <a href={`mailto:${complaint.complainantEmail}`} className="text-brand-blue hover:underline">
                        {complaint.complainantEmail}
                      </a>
                    ) : (
                      '—'
                    )}
                  </dd>
                </div>
              </dl>
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Reported Driver</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Name</dt>
                  <dd className="font-medium text-gray-900">{complaint.driverName}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Plate Number</dt>
                  <dd className="font-medium text-gray-900">{complaint.plateNumber}</dd>
                </div>
              </dl>
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Review record</h3>
              <div className="mt-2 space-y-3">
                {(
                  [
                    ['Investigation details', investigationNotes, setInvestigationNotes, 'What was looked into and found'],
                    ['Action taken', actionTaken, setActionTaken, 'e.g. spoke to the driver, issued a reminder'],
                    ['Approved sanction (if any)', sanction, setSanction, 'Only record a sanction that authorized personnel approved'],
                    ['Resolution', resolution, setResolution, 'How this ended'],
                  ] as const
                ).map(([label, value, set, placeholder]) => (
                  <label key={label} className="block text-xs font-medium text-gray-600">
                    {label}
                    <textarea
                      value={value}
                      onChange={(e) => set(e.target.value)}
                      rows={2}
                      placeholder={placeholder}
                      className="mt-1 w-full rounded-lg border border-border-subtle px-3 py-2 text-sm text-gray-900 focus:border-brand-blue focus:outline-none"
                    />
                  </label>
                ))}
              </div>
              <p className="mt-2 text-xs text-gray-400">
                A complaint never changes the driver's status by itself. Multiple complaints trigger a review, not automatic action — disciplinary status is changed separately under Fleet → Drivers.
              </p>
            </div>

            <div className="mt-auto grid grid-cols-3 gap-2 pt-2">
              <button
                onClick={() => handleSetStatus('INVESTIGATING')}
                disabled={isSubmitting || complaint.status === 'INVESTIGATING'}
                className="rounded-lg border border-brand-blue py-2 text-xs font-semibold text-brand-blue transition hover:bg-yellow-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                {COMPLAINT_STATUS_LABELS.INVESTIGATING}
              </button>
              <button
                onClick={() => handleSetStatus('RESOLVED')}
                disabled={isSubmitting || complaint.status === 'RESOLVED'}
                className="rounded-lg border border-status-good py-2 text-xs font-semibold text-status-good transition hover:bg-status-good-bg disabled:cursor-not-allowed disabled:opacity-50"
              >
                {COMPLAINT_STATUS_LABELS.RESOLVED}
              </button>
              <button
                onClick={() => handleSetStatus('REJECTED')}
                disabled={isSubmitting || complaint.status === 'REJECTED'}
                className="rounded-lg border border-status-critical py-2 text-xs font-semibold text-status-critical transition hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
              >
                {COMPLAINT_STATUS_LABELS.REJECTED}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
