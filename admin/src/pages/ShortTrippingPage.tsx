import { useEffect, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { Card, SectionHeader } from '../components/Card';
import { TableSkeleton } from '../components/Skeleton';
import { PaginationControls } from '../components/PaginationControls';
import { Modal, ModalActions } from '../components/Modal';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDateTime } from '../lib/formatDate';
import { canManageFleet, isAdminLevel, useAuth } from '../lib/auth';
import { IncidentBadge, errorMessage, inputClass, primaryButton, secondaryButton, type IncidentStatus } from '../lib/ops';

interface Incident {
  id: string;
  driverId: string;
  driverName: string;
  driverCode: string | null;
  plateNumber: string | null;
  route: string | null;
  intendedDestination: string | null;
  source: string;
  occurredAt: string;
  description: string | null;
  status: IncidentStatus;
  explanation: string | null;
  explanationSubmittedAt: string | null;
  reviewNote: string | null;
  reviewedAt: string | null;
  countedInRestriction: boolean;
}
interface IncidentsResponse {
  incidents: Incident[];
  currentPage: number;
  totalIncidents: number;
  totalPages: number;
}
interface RestrictionRow {
  id: string;
  driverId: string;
  driverName: string;
  reason: string;
  startsAt: string;
  expiresAt: string;
  durationMinutes: number;
  incidentIds: string[];
  appliedByName: string | null;
  liftedByName: string | null;
  liftNote: string | null;
  state: 'ACTIVE' | 'EXPIRED' | 'LIFTED';
}
interface RestrictionsResponse {
  restrictions: RestrictionRow[];
  currentPage: number;
  totalPages: number;
}
interface Setting {
  key: string;
  value: number | boolean | null;
}

const SOURCE_LABELS: Record<string, string> = {
  COMMUTER_COMPLAINT: 'Commuter complaint',
  OPERATOR_REPORT: 'Recorded by staff',
  DRIVER_SELF_REPORT: 'Driver',
};

const FILTERS: { label: string; query: string }[] = [
  { label: 'Open', query: 'open=1' },
  { label: 'All', query: '' },
  { label: 'Confirmed', query: 'status=CONFIRMED' },
  { label: 'Dismissed', query: 'status=DISMISSED' },
];

function ReviewModal({ incident, onClose, onDone }: { incident: Incident; onClose: () => void; onDone: (msg: string | null) => void }) {
  const { admin } = useAuth();
  const canReview = admin?.role !== undefined;
  const [note, setNote] = useState(incident.reviewNote ?? '');
  const [submitting, setSubmitting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function act(status: 'UNDER_REVIEW' | 'CONFIRMED' | 'DISMISSED' | 'DUPLICATE') {
    if (submitting) return;
    if (status !== 'UNDER_REVIEW' && note.trim().length === 0) {
      setError('Please record the reason for this decision first.');
      return;
    }
    setSubmitting(status);
    setError(null);
    try {
      const res = await apiClient.patch<{ restrictionApplied: { expiresAt: string } | null }>(`/api/admin/ops/incidents/${incident.id}/review`, {
        status,
        note: note.trim() || undefined,
      });
      onDone(res.restrictionApplied ? `A trip-start restriction was applied to ${incident.driverName} until ${formatManilaDateTime(res.restrictionApplied.expiresAt)}.` : null);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(null);
    }
  }

  const decided = incident.status === 'CONFIRMED' || incident.status === 'DISMISSED' || incident.status === 'DUPLICATE';

  return (
    <Modal title="Short-tripping report" subtitle={`${incident.driverName}${incident.plateNumber ? ` · ${incident.plateNumber}` : ''}`} onClose={onClose} wide>
      <div className="space-y-4 text-sm">
        <div className="flex items-center justify-between">
          <p className="text-gray-500">{formatManilaDateTime(incident.occurredAt)}</p>
          <IncidentBadge status={incident.status} />
        </div>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-2">
          <div>
            <dt className="text-xs text-gray-500">Route</dt>
            <dd className="font-medium text-gray-900">{incident.route ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Intended destination</dt>
            <dd className="font-medium text-gray-900">{incident.intendedDestination ?? '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Reported by</dt>
            <dd className="font-medium text-gray-900">{SOURCE_LABELS[incident.source] ?? incident.source}</dd>
          </div>
          <div>
            <dt className="text-xs text-gray-500">Counted toward a restriction</dt>
            <dd className="font-medium text-gray-900">{incident.countedInRestriction ? 'Yes' : 'No'}</dd>
          </div>
        </dl>
        {incident.description && (
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">What was reported</h3>
            <p className="mt-1 text-gray-800">{incident.description}</p>
          </div>
        )}
        <div>
          <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Driver's explanation</h3>
          {incident.explanation ? (
            <>
              <p className="mt-1 whitespace-pre-line text-gray-800">{incident.explanation}</p>
              {incident.explanationSubmittedAt && <p className="mt-1 text-xs text-gray-400">Submitted {formatManilaDateTime(incident.explanationSubmittedAt)}</p>}
            </>
          ) : (
            <p className="mt-1 text-gray-500">No explanation yet. The driver has been asked for one.</p>
          )}
        </div>
        {incident.reviewNote && decided && (
          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Recorded decision{incident.reviewedAt ? ` · ${formatManilaDateTime(incident.reviewedAt)}` : ''}</h3>
            <p className="mt-1 text-gray-800">{incident.reviewNote}</p>
          </div>
        )}

        {canReview && (
          <div>
            <label className="block text-sm font-medium text-gray-700">{decided ? 'Correct this record — reason' : 'Reason / review note'}</label>
            <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3} className={inputClass} placeholder="Recorded with your name against this decision" />
            <p className="mt-1.5 text-xs text-gray-400">
              GPS errors, network drops, app crashes, and genuine emergencies are not violations — dismiss those. Only <b>confirmed</b> reports count toward a restriction (under the current policy settings).
              Dismissing a confirmed report that was already counted corrects the record and lifts any restriction it caused.
            </p>
          </div>
        )}
        {error && <p className="font-medium text-brand-red">{error}</p>}
        {canReview && (
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <button onClick={() => act('UNDER_REVIEW')} disabled={!!submitting || incident.status === 'UNDER_REVIEW'} className={secondaryButton}>
              {submitting === 'UNDER_REVIEW' ? '...' : 'Under review'}
            </button>
            <button onClick={() => act('CONFIRMED')} disabled={!!submitting || incident.status === 'CONFIRMED'} className="rounded-lg border border-status-critical px-3 py-1.5 text-xs font-semibold text-status-critical transition hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50">
              {submitting === 'CONFIRMED' ? '...' : 'Confirm violation'}
            </button>
            <button onClick={() => act('DISMISSED')} disabled={!!submitting || incident.status === 'DISMISSED'} className="rounded-lg border border-status-good px-3 py-1.5 text-xs font-semibold text-status-good transition hover:bg-status-good-bg disabled:cursor-not-allowed disabled:opacity-50">
              {submitting === 'DISMISSED' ? '...' : 'Dismiss'}
            </button>
            <button onClick={() => act('DUPLICATE')} disabled={!!submitting || incident.status === 'DUPLICATE'} className={secondaryButton}>
              {submitting === 'DUPLICATE' ? '...' : 'Duplicate'}
            </button>
          </div>
        )}
      </div>
    </Modal>
  );
}

function RecordIncidentModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [drivers, setDrivers] = useState<{ id: string; fullName: string; driverId: string }[] | null>(null);
  const [driverId, setDriverId] = useState('');
  const [route, setRoute] = useState('');
  const [destination, setDestination] = useState('');
  const [description, setDescription] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiClient
      .get<{ drivers: { id: string; fullName: string; driverId: string }[] }>('/api/admin/ops/drivers?pageSize=100')
      .then((r) => setDrivers(r.drivers))
      .catch((err) => setError(errorMessage(err, 'Could not load drivers.')));
  }, []);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.post('/api/admin/ops/incidents', {
        driverId,
        description,
        ...(route.trim() ? { route: route.trim() } : {}),
        ...(destination.trim() ? { intendedDestination: destination.trim() } : {}),
      });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal title="Record an incident" subtitle="The driver is asked to explain. It does not count toward any restriction until it is reviewed and confirmed." onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Driver</label>
          <select required value={driverId} onChange={(e) => setDriverId(e.target.value)} className={inputClass}>
            <option value="">{drivers ? 'Select…' : 'Loading…'}</option>
            {drivers?.map((d) => (
              <option key={d.id} value={d.id}>
                {d.fullName} ({d.driverId})
              </option>
            ))}
          </select>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700">Route</label>
            <input value={route} onChange={(e) => setRoute(e.target.value)} placeholder="Pasig – Quiapo" className={inputClass} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Intended destination</label>
            <input value={destination} onChange={(e) => setDestination(e.target.value)} className={inputClass} />
          </div>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">What happened</label>
          <textarea required minLength={3} value={description} onChange={(e) => setDescription(e.target.value)} rows={4} className={inputClass} />
        </div>
        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Record incident" submitting={submitting} />
      </form>
    </Modal>
  );
}

function IncidentsTab({ initialDriverId }: { initialDriverId: string | null }) {
  const { admin } = useAuth();
  const [filter, setFilter] = useState(FILTERS[0]);
  const [page, setPage] = useState(1);
  const [data, setData] = useState<IncidentsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Incident | null>(null);
  const [recording, setRecording] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  function load() {
    const params = new URLSearchParams(filter.query);
    params.set('page', String(page));
    params.set('pageSize', '25');
    if (initialDriverId) params.set('driverId', initialDriverId);
    apiClient
      .get<IncidentsResponse>(`/api/admin/ops/incidents?${params.toString()}`)
      .then((r) => {
        setData(r);
        setError(null);
      })
      .catch((e) => setError(errorMessage(e, 'Could not load incidents.')));
  }
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, page, initialDriverId]);
  useEffect(() => setPage(1), [filter]);
  usePolling(load, 10_000);

  return (
    <Card className="mt-4">
      <SectionHeader
        icon={<span className="text-xs font-bold">!</span>}
        title="Short-tripping reports"
        action={
          canManageFleet(admin?.role) && (
            <button onClick={() => setRecording(true)} className={primaryButton}>
              Record incident
            </button>
          )
        }
      />
      {initialDriverId && <p className="mt-2 text-xs text-gray-500">Showing one driver's reports. Switch tabs or reload the page without the filter to see everyone.</p>}
      <div className="mt-3 flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <button key={f.label} onClick={() => setFilter(f)} className={`rounded-lg px-3.5 py-2 text-sm font-semibold transition ${filter.label === f.label ? 'bg-brand-blue text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            {f.label}
          </button>
        ))}
      </div>
      {notice && <p className="mt-4 rounded-lg bg-status-warning-bg px-4 py-3 text-sm font-medium text-status-warning">{notice}</p>}
      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!data && !error && <TableSkeleton columns={6} />}
      {data && data.incidents.length === 0 && <p className="mt-4 text-sm text-gray-500">No reports found.</p>}
      {data && data.incidents.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[860px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">When</th>
                <th className="px-4 py-3">Driver</th>
                <th className="px-4 py-3">Jeepney</th>
                <th className="px-4 py-3">Route</th>
                <th className="px-4 py-3">Source</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Counted</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {data.incidents.map((i) => (
                <tr key={i.id} onClick={() => setSelected(i)} className="cursor-pointer transition hover:bg-gray-50">
                  <td className="px-4 py-3 text-gray-600">{formatManilaDateTime(i.occurredAt)}</td>
                  <td className="px-4 py-3 font-medium text-gray-900">{i.driverName}</td>
                  <td className="px-4 py-3 text-gray-600">{i.plateNumber ?? '—'}</td>
                  <td className="px-4 py-3 text-gray-600">{i.route ?? '—'}</td>
                  <td className="px-4 py-3 text-gray-600">{SOURCE_LABELS[i.source] ?? i.source}</td>
                  <td className="px-4 py-3">
                    <IncidentBadge status={i.status} />
                  </td>
                  <td className="px-4 py-3 text-gray-600">{i.countedInRestriction ? 'Yes' : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {data && <PaginationControls currentPage={data.currentPage} totalPages={data.totalPages} hasNextPage={data.currentPage < data.totalPages} onPageChange={setPage} />}

      {selected && (
        <ReviewModal
          incident={selected}
          onClose={() => setSelected(null)}
          onDone={(msg) => {
            setSelected(null);
            setNotice(msg);
            load();
          }}
        />
      )}
      {recording && (
        <RecordIncidentModal
          onClose={() => setRecording(false)}
          onDone={() => {
            setRecording(false);
            load();
          }}
        />
      )}
    </Card>
  );
}

function ApplyRestrictionModal({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [drivers, setDrivers] = useState<{ id: string; fullName: string }[] | null>(null);
  const [driverId, setDriverId] = useState('');
  const [minutes, setMinutes] = useState('60');
  const [reason, setReason] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    apiClient.get<{ drivers: { id: string; fullName: string }[] }>('/api/admin/ops/drivers?pageSize=100').then((r) => setDrivers(r.drivers)).catch((e) => setError(errorMessage(e)));
  }, []);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.post('/api/admin/ops/restrictions', { driverId, durationMinutes: Number(minutes), reason });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }
  return (
    <Modal title="Apply a restriction" subtitle="Blocks the driver from starting a new trip. A trip already in progress is not stopped." onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <select required value={driverId} onChange={(e) => setDriverId(e.target.value)} className={inputClass}>
          <option value="">{drivers ? 'Select driver…' : 'Loading…'}</option>
          {drivers?.map((d) => (
            <option key={d.id} value={d.id}>
              {d.fullName}
            </option>
          ))}
        </select>
        <div>
          <label className="block text-sm font-medium text-gray-700">Duration (minutes)</label>
          <input type="number" min={1} required value={minutes} onChange={(e) => setMinutes(e.target.value)} className={inputClass} />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Reason (shown to the driver)</label>
          <textarea required minLength={3} value={reason} onChange={(e) => setReason(e.target.value)} rows={3} className={inputClass} />
        </div>
        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Apply restriction" submitting={submitting} danger />
      </form>
    </Modal>
  );
}

function RestrictionsTab() {
  const { admin } = useAuth();
  const [page, setPage] = useState(1);
  const [activeOnly, setActiveOnly] = useState(true);
  const [data, setData] = useState<RestrictionsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lifting, setLifting] = useState<RestrictionRow | null>(null);
  const [liftNote, setLiftNote] = useState('');
  const [liftError, setLiftError] = useState<string | null>(null);
  const [applying, setApplying] = useState(false);

  function load() {
    const params = new URLSearchParams({ page: String(page), pageSize: '25' });
    if (activeOnly) params.set('active', '1');
    apiClient
      .get<RestrictionsResponse>(`/api/admin/ops/restrictions?${params.toString()}`)
      .then((r) => {
        setData(r);
        setError(null);
      })
      .catch((e) => setError(errorMessage(e, 'Could not load restrictions.')));
  }
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, activeOnly]);
  useEffect(() => setPage(1), [activeOnly]);
  usePolling(load, 15_000);

  async function lift(e: FormEvent) {
    e.preventDefault();
    if (!lifting) return;
    setLiftError(null);
    try {
      await apiClient.post(`/api/admin/ops/restrictions/${lifting.id}/lift`, { note: liftNote });
      setLifting(null);
      setLiftNote('');
      load();
    } catch (err) {
      setLiftError(errorMessage(err));
    }
  }

  return (
    <Card className="mt-4">
      <SectionHeader
        icon={<span className="text-xs font-bold">⏱</span>}
        title="Trip-start restrictions"
        action={
          isAdminLevel(admin?.role) && (
            <button onClick={() => setApplying(true)} className={secondaryButton}>
              Apply manually
            </button>
          )
        }
      />
      <label className="mt-3 flex items-center gap-2 text-sm text-gray-600">
        <input type="checkbox" checked={activeOnly} onChange={(e) => setActiveOnly(e.target.checked)} />
        Only restrictions in force now
      </label>
      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!data && !error && <TableSkeleton columns={6} />}
      {data && data.restrictions.length === 0 && <p className="mt-4 text-sm text-gray-500">No restrictions.</p>}
      {data && data.restrictions.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[900px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">Driver</th>
                <th className="px-4 py-3">State</th>
                <th className="px-4 py-3">Started</th>
                <th className="px-4 py-3">Ends</th>
                <th className="px-4 py-3">Incidents</th>
                <th className="px-4 py-3">Applied by</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {data.restrictions.map((r) => (
                <tr key={r.id}>
                  <td className="px-4 py-3 font-medium text-gray-900">{r.driverName}</td>
                  <td className="px-4 py-3">
                    <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ${r.state === 'ACTIVE' ? 'bg-status-critical-bg text-status-critical' : 'bg-gray-100 text-gray-600'}`}>
                      {r.state === 'ACTIVE' ? 'In force' : r.state === 'LIFTED' ? 'Lifted' : 'Expired'}
                    </span>
                    {r.liftNote && <p className="mt-1 max-w-[220px] text-xs text-gray-500">{r.liftNote}</p>}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{formatManilaDateTime(r.startsAt)}</td>
                  <td className="px-4 py-3 text-gray-600">{formatManilaDateTime(r.expiresAt)}</td>
                  <td className="px-4 py-3 tabular-nums text-gray-600">{r.incidentIds.length || '—'}</td>
                  <td className="px-4 py-3 text-gray-600">{r.appliedByName ?? 'System'}</td>
                  <td className="px-4 py-3 text-right">
                    {r.state === 'ACTIVE' && canManageFleet(admin?.role) && (
                      <button onClick={() => setLifting(r)} className={secondaryButton}>
                        Lift
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {data && <PaginationControls currentPage={data.currentPage} totalPages={data.totalPages} hasNextPage={data.currentPage < data.totalPages} onPageChange={setPage} />}

      {lifting && (
        <Modal title="Lift restriction" subtitle={lifting.driverName} onClose={() => setLifting(null)}>
          <form onSubmit={lift}>
            <label className="block text-sm font-medium text-gray-700">Why is it being lifted? (recorded)</label>
            <textarea required minLength={3} value={liftNote} onChange={(e) => setLiftNote(e.target.value)} rows={3} className={inputClass} />
            {liftError && <p className="mt-3 text-sm font-medium text-brand-red">{liftError}</p>}
            <ModalActions onCancel={() => setLifting(null)} submitLabel="Lift restriction" submitting={false} />
          </form>
        </Modal>
      )}
      {applying && (
        <ApplyRestrictionModal
          onClose={() => setApplying(false)}
          onDone={() => {
            setApplying(false);
            load();
          }}
        />
      )}
    </Card>
  );
}

export default function ShortTrippingPage() {
  const [searchParams] = useSearchParams();
  const driverId = searchParams.get('driverId');
  const [tab, setTab] = useState<'incidents' | 'restrictions'>('incidents');
  const [settings, setSettings] = useState<Setting[] | null>(null);

  useEffect(() => {
    apiClient
      .get<{ settings: Setting[] }>('/api/admin/ops/settings')
      .then((r) => setSettings(r.settings))
      .catch(() => setSettings(null));
  }, []);
  const get = (k: string) => settings?.find((s) => s.key === k)?.value;

  return (
    <DashboardLayout title="Short-Tripping">
      <p className="text-sm text-gray-500">Passengers made to get off before their destination: drivers explain, reviewers decide, and repeat confirmed violations can temporarily restrict starting new trips.</p>

      {settings && (
        <p className="mt-4 rounded-lg bg-yellow-50 px-4 py-3 text-sm text-yellow-900">
          <b>Proposed policy — not yet confirmed by MANIBELA.</b> A driver is restricted from starting a new trip for {String(get('shortTripRestrictionMinutes'))} minutes once they reach{' '}
          {String(get('shortTripRestrictionThreshold'))} qualifying incidents. Counting: {get('shortTripCountOnlyConfirmed') ? 'confirmed incidents only' : 'every non-dismissed report'}. These values are adjustable under Settings → Business Rules.
        </p>
      )}

      <div className="mt-4 flex gap-2">
        {(['incidents', 'restrictions'] as const).map((t) => (
          <button key={t} onClick={() => setTab(t)} className={`rounded-lg px-3.5 py-2 text-sm font-semibold transition ${tab === t ? 'bg-brand-blue text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
            {t === 'incidents' ? 'Reports' : 'Restrictions'}
          </button>
        ))}
      </div>
      {tab === 'incidents' ? <IncidentsTab initialDriverId={driverId} /> : <RestrictionsTab />}
    </DashboardLayout>
  );
}
