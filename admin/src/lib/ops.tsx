import { ApiError } from './apiClient';

/** Types and small UI atoms shared by the fleet pages (Operations, Fleet,
 * Short-Tripping, Fleet Reports). Shapes mirror backend/src/routes/ops.ts. */

export type OccupancyLevel = 'NORMAL' | 'NEARLY_FULL' | 'FULL' | 'UNKNOWN';

export interface Occupancy {
  tripId: string;
  plateNumber: string | null;
  appPassengers: number;
  manualPassengers: number;
  totalPassengers: number;
  seatingCapacity: number | null;
  remainingSeats: number | null;
  status: OccupancyLevel;
  nearFullThresholdPercent: number;
}

export type OperationalStatus = 'ACTIVE' | 'INACTIVE';
export type DisciplinaryStatus = 'NONE' | 'WARNING' | 'UNDER_INVESTIGATION' | 'SUSPENDED';
export type IncidentStatus = 'PENDING_EXPLANATION' | 'EXPLAINED' | 'UNDER_REVIEW' | 'CONFIRMED' | 'DISMISSED' | 'DUPLICATE';

export interface Restriction {
  id: string;
  reason: string;
  startsAt: string;
  expiresAt: string;
  durationMinutes: number;
  secondsRemaining: number;
}

export const DISCIPLINARY_LABELS: Record<DisciplinaryStatus, string> = {
  NONE: 'None',
  WARNING: 'Warning',
  UNDER_INVESTIGATION: 'Under Investigation',
  SUSPENDED: 'Suspended',
};

export const INCIDENT_STATUS_LABELS: Record<IncidentStatus, string> = {
  PENDING_EXPLANATION: 'Awaiting explanation',
  EXPLAINED: 'Explained',
  UNDER_REVIEW: 'Under review',
  CONFIRMED: 'Confirmed',
  DISMISSED: 'Dismissed',
  DUPLICATE: 'Duplicate',
};

export function errorMessage(err: unknown, fallback = 'Something went wrong. Please try again.'): string {
  return err instanceof ApiError ? err.message : fallback;
}

function Pill({ className, children }: { className: string; children: string }) {
  return <span className={`inline-flex items-center whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold ${className}`}>{children}</span>;
}

export function OccupancyBadge({ status }: { status: OccupancyLevel | null }) {
  if (!status) return <span className="text-xs text-gray-400">—</span>;
  switch (status) {
    case 'FULL':
      return <Pill className="bg-status-critical-bg text-status-critical">FULL</Pill>;
    case 'NEARLY_FULL':
      return <Pill className="bg-status-warning-bg text-status-warning">NEARLY FULL</Pill>;
    case 'NORMAL':
      return <Pill className="bg-status-good-bg text-status-good">NORMAL</Pill>;
    default:
      return <Pill className="bg-gray-100 text-gray-500">No capacity</Pill>;
  }
}

export function OperationalBadge({ status }: { status: OperationalStatus }) {
  return status === 'ACTIVE' ? (
    <Pill className="bg-status-good-bg text-status-good">Active</Pill>
  ) : (
    <Pill className="bg-gray-100 text-gray-600">Inactive</Pill>
  );
}

export function DisciplinaryBadge({ status }: { status: DisciplinaryStatus }) {
  const cls =
    status === 'NONE'
      ? 'bg-gray-100 text-gray-600'
      : status === 'WARNING'
        ? 'bg-status-warning-bg text-status-warning'
        : 'bg-status-critical-bg text-status-critical';
  return <Pill className={cls}>{DISCIPLINARY_LABELS[status]}</Pill>;
}

export function IncidentBadge({ status }: { status: IncidentStatus }) {
  const cls =
    status === 'CONFIRMED'
      ? 'bg-status-critical-bg text-status-critical'
      : status === 'DISMISSED' || status === 'DUPLICATE'
        ? 'bg-gray-100 text-gray-600'
        : status === 'PENDING_EXPLANATION'
          ? 'bg-status-warning-bg text-status-warning'
          : 'bg-yellow-200 text-yellow-900';
  return <Pill className={cls}>{INCIDENT_STATUS_LABELS[status]}</Pill>;
}

export function peso(n: number | null | undefined): string {
  if (n === null || n === undefined) return '—';
  return `₱${n.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export const inputClass =
  'mt-1.5 w-full rounded-lg border border-border-subtle bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-blue focus:outline-none';

export const secondaryButton =
  'rounded-lg border border-border-subtle px-3 py-1.5 text-xs font-semibold text-gray-600 transition hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';

export const primaryButton =
  'rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60';
