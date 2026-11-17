import { useEffect, useState, type FormEvent } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { Card, SectionHeader } from '../components/Card';
import { StatCardSkeleton, TableSkeleton } from '../components/Skeleton';
import { Modal, ModalActions } from '../components/Modal';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDate, formatManilaTime, manilaDateString } from '../lib/formatDate';
import { canManageFleet, useAuth } from '../lib/auth';
import { errorMessage, inputClass, peso, secondaryButton } from '../lib/ops';
import {
  addNote,
  addSectionHeader,
  addTable,
  addTitleBlock,
  downloadCsv,
  money,
  type CsvRows,
} from '../lib/csvExport';

interface ReportResponse {
  period: 'day' | 'month';
  label: string;
  totals: {
    trips: number;
    completedTrips: number;
    activeTrips: number;
    appPassengers: number;
    manualPassengers: number;
    totalPassengers: number;
    incidents: number;
    complaints: number;
  };
  earnings: {
    driverReported: number;
    driverReportedLogs: number;
    estimated: number | null;
    estimatedFare: number | null;
    verified: number | null;
    verifiedLogs: number;
    unverifiedLogs: number;
  };
  drivers: { driverId: string; driverName: string; trips: number; completedTrips: number; appPassengers: number; manualPassengers: number; daysOperated: number; daysInPeriod: number }[];
  driversNotOperating: { driverId: string; driverName: string; reasons: { date: string; reason: string }[] }[];
  trips: {
    id: string;
    date: string;
    driverName: string;
    plateNumber: string | null;
    route: string | null;
    status: string;
    startedAt: string;
    endedAt: string | null;
    seatingCapacity: number | null;
    appPassengers: number;
    manualPassengers: number;
    totalPassengers: number;
    peakOccupancy: number;
  }[];
  earningsLogs: { id: string; date: string; driverName: string; driverReported: number; verified: number | null; verificationNote: string | null }[];
}

function VerifyModal({ log, onClose, onDone }: { log: ReportResponse['earningsLogs'][number]; onClose: () => void; onDone: () => void }) {
  const [amount, setAmount] = useState(log.verified?.toString() ?? '');
  const [note, setNote] = useState(log.verificationNote ?? '');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.post(`/api/admin/ops/earnings/${log.id}/verify`, { verifiedEarnings: Number(amount), note: note.trim() || undefined });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }
  return (
    <Modal title="Verify earnings" subtitle={`${log.driverName} · ${log.date} · driver reported ${peso(log.driverReported)}`} onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Verified amount (₱)</label>
          <input type="number" min={0} step="0.01" required value={amount} onChange={(e) => setAmount(e.target.value)} className={inputClass} />
          <p className="mt-1.5 text-xs text-gray-400">Enter what was actually confirmed through MANIBELA's collection and remittance process — not a passenger-count estimate.</p>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Note (optional)</label>
          <input value={note} onChange={(e) => setNote(e.target.value)} className={inputClass} />
        </div>
        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Save verified amount" submitting={submitting} />
      </form>
    </Modal>
  );
}

function Icon({ d }: { d: string }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d={d} />
    </svg>
  );
}

export default function FleetReportsPage() {
  const { admin } = useAuth();
  const [period, setPeriod] = useState<'day' | 'month'>('day');
  const [day, setDay] = useState(manilaDateString());
  const [month, setMonth] = useState(manilaDateString().slice(0, 7));
  const [report, setReport] = useState<ReportResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [verifying, setVerifying] = useState<ReportResponse['earningsLogs'][number] | null>(null);

  const date = period === 'day' ? day : month;

  function load() {
    apiClient
      .get<ReportResponse>(`/api/admin/ops/reports?period=${period}&date=${date}`)
      .then((r) => {
        setReport(r);
        setError(null);
      })
      .catch((e) => setError(errorMessage(e, 'Could not load the report.')));
  }
  useEffect(() => {
    setReport(null);
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [period, date]);
  usePolling(load, 30_000);

  function exportCsv() {
    if (!report) return;
    const rows: CsvRows = [];
    addTitleBlock(rows, `Fleet ${period === 'day' ? 'Daily' : 'Monthly'} Report — ${report.label}`, []);
    addSectionHeader(rows, 'Totals');
    addTable(
      rows,
      [
        { header: 'Trips', type: 'number' },
        { header: 'Completed', type: 'number' },
        { header: 'App passengers', type: 'number' },
        { header: 'Manual passengers', type: 'number' },
        { header: 'Total passengers', type: 'number' },
        { header: 'Short-tripping reports', type: 'number' },
        { header: 'Complaints', type: 'number' },
      ],
      [[report.totals.trips, report.totals.completedTrips, report.totals.appPassengers, report.totals.manualPassengers, report.totals.totalPassengers, report.totals.incidents, report.totals.complaints]],
    );
    addSectionHeader(rows, 'Earnings (kept separate)');
    addTable(
      rows,
      [
        { header: 'Driver-reported (PHP)', type: 'number' },
        { header: 'Estimated (PHP) — not income', type: 'number' },
        { header: 'Verified (PHP)', type: 'number' },
      ],
      [[money(report.earnings.driverReported), report.earnings.estimated === null ? null : money(report.earnings.estimated), report.earnings.verified === null ? null : money(report.earnings.verified)]],
    );
    addNote(rows, 'Estimated = passengers x configured fare. It is only an estimate and is never treated as actual income.');
    addSectionHeader(rows, 'Trips');
    addTable(
      rows,
      [
        { header: 'Date', type: 'text' },
        { header: 'Driver', type: 'text' },
        { header: 'Plate', type: 'text' },
        { header: 'Route', type: 'text' },
        { header: 'Capacity', type: 'number' },
        { header: 'App passengers', type: 'number' },
        { header: 'Manual passengers', type: 'number' },
        { header: 'Total passengers', type: 'number' },
        { header: 'Peak on board', type: 'number' },
      ],
      report.trips.map((t) => [t.date, t.driverName, t.plateNumber, t.route, t.seatingCapacity, t.appPassengers, t.manualPassengers, t.totalPassengers, t.peakOccupancy]),
    );
    downloadCsv(rows, `fleet-report-${report.label}.csv`);
  }

  return (
    <DashboardLayout title="Fleet Reports">
      <p className="text-sm text-gray-500">Daily and monthly operations: trips, passenger counts against capacity, and earnings kept in three separate figures.</p>

      <div className="mt-4 flex flex-wrap items-center gap-3">
        <div className="flex gap-2">
          {(['day', 'month'] as const).map((p) => (
            <button key={p} onClick={() => setPeriod(p)} className={`rounded-lg px-3.5 py-2 text-sm font-semibold transition ${period === p ? 'bg-brand-blue text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
              {p === 'day' ? 'Daily' : 'Monthly'}
            </button>
          ))}
        </div>
        {period === 'day' ? (
          <input type="date" value={day} max={manilaDateString()} onChange={(e) => e.target.value && setDay(e.target.value)} className="rounded-lg border border-border-subtle px-3 py-2 text-sm" />
        ) : (
          <input type="month" value={month} max={manilaDateString().slice(0, 7)} onChange={(e) => e.target.value && setMonth(e.target.value)} className="rounded-lg border border-border-subtle px-3 py-2 text-sm" />
        )}
        <button onClick={exportCsv} disabled={!report} className={secondaryButton}>
          Export CSV
        </button>
      </div>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}

      {!report && !error && (
        <div className="mt-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <StatCardSkeleton key={i} />
          ))}
        </div>
      )}

      {report && (
        <>
          <div className="mt-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
            <StatCard label="Trips" value={report.totals.trips} icon={<Icon d="M5 6a2 2 0 1 0 0-.01M19 18a2 2 0 1 0 0-.01M5 8v5a4 4 0 0 0 4 4h6" />} changeLabel="" />
            <StatCard label="App passengers" value={report.totals.appPassengers} icon={<Icon d="M3 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6M9.5 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z" />} />
            <StatCard label="Manual passengers" value={report.totals.manualPassengers} icon={<Icon d="M3 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6M9.5 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z" />} />
            <StatCard label="Total passengers" value={report.totals.totalPassengers} icon={<Icon d="M3 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6M9.5 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z" />} />
          </div>

          <Card className="mt-6">
            <SectionHeader icon={<span className="text-xs font-bold">₱</span>} title="Earnings — three different things" />
            <div className="mt-4 grid gap-4 sm:grid-cols-3">
              <div className="rounded-lg border border-border-subtle p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Driver-reported</p>
                <p className="mt-1 font-display text-2xl font-semibold text-gray-900">{peso(report.earnings.driverReported)}</p>
                <p className="mt-1 text-xs text-gray-500">What drivers entered in their Daily Operations log ({report.earnings.driverReportedLogs} log{report.earnings.driverReportedLogs === 1 ? '' : 's'}). Self-reported.</p>
              </div>
              <div className="rounded-lg border border-border-subtle p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Estimated</p>
                <p className="mt-1 font-display text-2xl font-semibold text-gray-900">{report.earnings.estimated === null ? 'Not enabled' : peso(report.earnings.estimated)}</p>
                <p className="mt-1 text-xs text-gray-500">
                  {report.earnings.estimated === null
                    ? 'Set a fare under Settings → Business Rules to show a passenger-count estimate.'
                    : `Passengers × ${peso(report.earnings.estimatedFare)}. An estimate only — not income.`}
                </p>
              </div>
              <div className="rounded-lg border border-border-subtle p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Verified</p>
                <p className="mt-1 font-display text-2xl font-semibold text-gray-900">{report.earnings.verified === null ? 'None yet' : peso(report.earnings.verified)}</p>
                <p className="mt-1 text-xs text-gray-500">
                  Confirmed against actual collection/remittance. {report.earnings.verifiedLogs} verified, {report.earnings.unverifiedLogs} not yet.
                </p>
              </div>
            </div>
            <p className="mt-3 text-xs text-gray-400">These are never converted into each other automatically.</p>
          </Card>

          <Card className="mt-6">
            <SectionHeader icon={<span className="text-xs font-bold">#</span>} title="By driver" />
            {report.drivers.length === 0 ? (
              <p className="mt-4 text-sm text-gray-500">No trips in this period.</p>
            ) : (
              <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
                <table className="w-full min-w-[720px] text-left text-sm">
                  <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    <tr>
                      <th className="px-4 py-3">Driver</th>
                      <th className="px-4 py-3">Trips</th>
                      <th className="px-4 py-3">Completed</th>
                      <th className="px-4 py-3">App</th>
                      <th className="px-4 py-3">Manual</th>
                      <th className="px-4 py-3">Days operated</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {report.drivers.map((d) => (
                      <tr key={d.driverId}>
                        <td className="px-4 py-3 font-medium text-gray-900">{d.driverName}</td>
                        <td className="px-4 py-3 tabular-nums">{d.trips}</td>
                        <td className="px-4 py-3 tabular-nums">{d.completedTrips}</td>
                        <td className="px-4 py-3 tabular-nums">{d.appPassengers}</td>
                        <td className="px-4 py-3 tabular-nums">{d.manualPassengers}</td>
                        <td className="px-4 py-3 tabular-nums">
                          {d.daysOperated} / {d.daysInPeriod}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {report.driversNotOperating.length > 0 && (
              <div className="mt-5">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Did not operate in this period</h3>
                <ul className="mt-2 divide-y divide-gray-100 rounded-lg border border-border-subtle text-sm">
                  {report.driversNotOperating.map((d) => (
                    <li key={d.driverId} className="px-4 py-2.5">
                      <span className="font-medium text-gray-800">{d.driverName}</span>
                      {d.reasons.length === 0 ? (
                        <span className="ml-2 text-xs text-gray-400">no reason recorded</span>
                      ) : (
                        <span className="ml-2 text-xs text-gray-500">{d.reasons.map((r) => `${r.date}: ${r.reason}`).join(' · ')}</span>
                      )}
                    </li>
                  ))}
                </ul>
                <p className="mt-2 text-xs text-gray-400">"Operated" is read from real trip records. Reasons are only what drivers chose to record.</p>
              </div>
            )}
          </Card>

          <Card className="mt-6">
            <SectionHeader icon={<span className="text-xs font-bold">≡</span>} title="Trips" />
            {report.trips.length === 0 ? (
              <p className="mt-4 text-sm text-gray-500">No trips in this period.</p>
            ) : (
              <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
                <table className="w-full min-w-[960px] text-left text-sm">
                  <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    <tr>
                      <th className="px-4 py-3">Date</th>
                      <th className="px-4 py-3">Driver</th>
                      <th className="px-4 py-3">Plate</th>
                      <th className="px-4 py-3">Time</th>
                      <th className="px-4 py-3">Capacity</th>
                      <th className="px-4 py-3">App</th>
                      <th className="px-4 py-3">Manual</th>
                      <th className="px-4 py-3">Total</th>
                      <th className="px-4 py-3">Peak</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {report.trips.map((t) => (
                      <tr key={t.id}>
                        <td className="px-4 py-3 text-gray-600">{formatManilaDate(t.startedAt)}</td>
                        <td className="px-4 py-3 font-medium text-gray-900">{t.driverName}</td>
                        <td className="px-4 py-3 text-gray-600">{t.plateNumber ?? '—'}</td>
                        <td className="px-4 py-3 text-gray-600">
                          {formatManilaTime(t.startedAt)} – {t.endedAt ? formatManilaTime(t.endedAt) : 'ongoing'}
                        </td>
                        <td className="px-4 py-3 tabular-nums">{t.seatingCapacity ?? '—'}</td>
                        <td className="px-4 py-3 tabular-nums">{t.appPassengers}</td>
                        <td className="px-4 py-3 tabular-nums">{t.manualPassengers}</td>
                        <td className="px-4 py-3 font-semibold tabular-nums">{t.totalPassengers}</td>
                        <td className="px-4 py-3 tabular-nums">{t.peakOccupancy}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          <Card className="mt-6">
            <SectionHeader icon={<span className="text-xs font-bold">✓</span>} title="Earnings records" />
            {report.earningsLogs.length === 0 ? (
              <p className="mt-4 text-sm text-gray-500">No driver earnings logs in this period.</p>
            ) : (
              <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
                <table className="w-full min-w-[680px] text-left text-sm">
                  <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    <tr>
                      <th className="px-4 py-3">Date</th>
                      <th className="px-4 py-3">Driver</th>
                      <th className="px-4 py-3">Driver-reported</th>
                      <th className="px-4 py-3">Verified</th>
                      {canManageFleet(admin?.role) && <th className="px-4 py-3" />}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {report.earningsLogs.map((l) => (
                      <tr key={l.id}>
                        <td className="px-4 py-3 text-gray-600">{l.date}</td>
                        <td className="px-4 py-3 font-medium text-gray-900">{l.driverName}</td>
                        <td className="px-4 py-3 tabular-nums">{peso(l.driverReported)}</td>
                        <td className="px-4 py-3 tabular-nums">{l.verified === null ? <span className="text-gray-400">Not verified</span> : peso(l.verified)}</td>
                        {canManageFleet(admin?.role) && (
                          <td className="px-4 py-3 text-right">
                            <button onClick={() => setVerifying(l)} className={secondaryButton}>
                              {l.verified === null ? 'Verify' : 'Edit'}
                            </button>
                          </td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>
        </>
      )}
      {!report && !error && <TableSkeleton columns={6} />}

      {verifying && (
        <VerifyModal
          log={verifying}
          onClose={() => setVerifying(null)}
          onDone={() => {
            setVerifying(null);
            load();
          }}
        />
      )}
    </DashboardLayout>
  );
}
