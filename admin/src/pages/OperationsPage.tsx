import { useEffect, useState } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { Card, SectionHeader } from '../components/Card';
import { StatCardSkeleton, TableSkeleton } from '../components/Skeleton';
import { PaginationControls } from '../components/PaginationControls';
import { Modal } from '../components/Modal';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDate, formatManilaDateTime, formatManilaTime } from '../lib/formatDate';
import { ROLE_LABELS, useAuth, type AdminRole } from '../lib/auth';
import { OccupancyBadge, errorMessage, secondaryButton, type OccupancyLevel } from '../lib/ops';

interface Overview {
  drivers: number;
  vehicles: number;
  vehiclesMissingCapacity: number;
  activeTrips: number;
  completedTripsToday: number;
  jeepneysNearlyFull: number;
  jeepneysFull: number;
  passengersOnBoard: number;
  openIncidents: number;
  activeRestrictions: number;
  role: AdminRole;
}

interface TripRow {
  id: string;
  driverName: string;
  plateNumber: string | null;
  route: string | null;
  status: 'ACTIVE' | 'COMPLETED';
  startedAt: string;
  endedAt: string | null;
  seatingCapacity: number | null;
  appPassengers: number;
  manualPassengers: number;
  totalPassengers: number;
  peakOccupancy: number;
  occupancyStatus: OccupancyLevel | null;
  remainingSeats: number | null;
}

interface TripsResponse {
  trips: TripRow[];
  currentPage: number;
  totalTrips: number;
  totalPages: number;
}

interface TripDetail {
  trip: { id: string; driverName: string; plateNumber: string | null; route: string | null; startedAt: string; endedAt: string | null; peakOccupancy: number };
  occupancy: { appPassengers: number; manualPassengers: number; totalPassengers: number; seatingCapacity: number | null } | null;
  manualAdjustments: { id: string; delta: number; countAfter: number; createdAt: string; undoOfId: string | null }[];
  appBoardings: { id: string; boardedAt: string; alightedAt: string | null; status: string; riders: number | null }[];
}

function Icon({ d }: { d: string }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d={d} />
    </svg>
  );
}
const ICONS = {
  people: 'M3 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6M9.5 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4Z',
  bus: 'M4 5h16v11H4zM4 11h16M7 19v-3M17 19v-3',
  route: 'M5 6a2 2 0 1 0 0-.01M19 18a2 2 0 1 0 0-.01M5 8v5a4 4 0 0 0 4 4h6',
  alert: 'M12 3.5 2.5 20h19L12 3.5ZM12 10v4.5M12 17.5h.01',
  block: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM5.6 5.6l12.8 12.8',
};

function PassengerCells({ t }: { t: Pick<TripRow, 'appPassengers' | 'manualPassengers' | 'totalPassengers' | 'seatingCapacity'> }) {
  return (
    <>
      <td className="px-4 py-3 tabular-nums text-gray-700">{t.appPassengers}</td>
      <td className="px-4 py-3 tabular-nums text-gray-700">{t.manualPassengers}</td>
      <td className="px-4 py-3 font-semibold tabular-nums text-gray-900">{t.totalPassengers}</td>
      <td className="px-4 py-3 tabular-nums text-gray-700">{t.seatingCapacity ?? '—'}</td>
    </>
  );
}

function TripDetailModal({ tripId, onClose }: { tripId: string; onClose: () => void }) {
  const [detail, setDetail] = useState<TripDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiClient
      .get<TripDetail>(`/api/admin/ops/trips/${tripId}`)
      .then(setDetail)
      .catch((err) => setError(errorMessage(err, 'Could not load this trip.')));
  }, [tripId]);

  return (
    <Modal title="Trip passenger record" subtitle={detail ? `${detail.trip.driverName} · ${detail.trip.plateNumber ?? '—'}` : undefined} onClose={onClose} wide>
      {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
      {!detail && !error && <p className="text-sm text-gray-500">Loading...</p>}
      {detail && (
        <div className="space-y-5 text-sm">
          <dl className="grid grid-cols-2 gap-x-6 gap-y-2 sm:grid-cols-4">
            {[
              ['App passengers', detail.occupancy?.appPassengers ?? 0],
              ['Manual passengers', detail.occupancy?.manualPassengers ?? 0],
              ['Total now', detail.occupancy?.totalPassengers ?? 0],
              ['Peak', detail.trip.peakOccupancy],
            ].map(([label, value]) => (
              <div key={label as string}>
                <dt className="text-xs text-gray-500">{label}</dt>
                <dd className="font-display text-xl font-semibold text-gray-900">{value}</dd>
              </div>
            ))}
          </dl>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Manual count changes (by the driver)</h3>
            {detail.manualAdjustments.length === 0 ? (
              <p className="mt-2 text-gray-500">None recorded.</p>
            ) : (
              <ul className="mt-2 divide-y divide-gray-100 rounded-lg border border-border-subtle">
                {detail.manualAdjustments.map((a) => (
                  <li key={a.id} className="flex items-center justify-between px-3 py-2">
                    <span className="font-medium text-gray-800">
                      {a.delta > 0 ? '+1' : '−1'}
                      {a.undoOfId && <span className="ml-2 text-xs font-normal text-gray-400">(undo)</span>}
                    </span>
                    <span className="text-xs text-gray-500">
                      count → {a.countAfter} · {formatManilaDateTime(a.createdAt)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">App boardings (GPS-verified)</h3>
            {detail.appBoardings.length === 0 ? (
              <p className="mt-2 text-gray-500">None recorded.</p>
            ) : (
              <ul className="mt-2 divide-y divide-gray-100 rounded-lg border border-border-subtle">
                {detail.appBoardings.map((b) => (
                  <li key={b.id} className="flex items-center justify-between px-3 py-2">
                    <span className="font-medium text-gray-800">
                      {b.riders ?? 1} rider{(b.riders ?? 1) === 1 ? '' : 's'}
                      <span className="ml-2 text-xs font-normal text-gray-400">{b.status.toLowerCase()}</span>
                    </span>
                    <span className="text-xs text-gray-500">
                      {formatManilaTime(b.boardedAt)} → {b.alightedAt ? formatManilaTime(b.alightedAt) : 'on board'}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}
    </Modal>
  );
}

export default function OperationsPage() {
  const { admin } = useAuth();
  const [overview, setOverview] = useState<Overview | null>(null);
  const [active, setActive] = useState<TripRow[] | null>(null);
  const [history, setHistory] = useState<TripsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [openTripId, setOpenTripId] = useState<string | null>(null);

  function fetchLive() {
    apiClient.get<Overview>('/api/admin/ops/overview').then(setOverview).catch((e) => setError(errorMessage(e)));
    apiClient
      .get<TripsResponse>('/api/admin/ops/trips?status=ACTIVE&pageSize=100')
      .then((r) => {
        setActive(r.trips);
        setError(null);
      })
      .catch((e) => setError(errorMessage(e, 'Could not load active trips.')));
  }

  function fetchHistory() {
    const params = new URLSearchParams({ status: 'COMPLETED', page: String(page), pageSize: '20' });
    if (from) params.set('from', from);
    if (to) params.set('to', to);
    apiClient
      .get<TripsResponse>(`/api/admin/ops/trips?${params.toString()}`)
      .then(setHistory)
      .catch((e) => setError(errorMessage(e, 'Could not load trips.')));
  }

  useEffect(fetchLive, []);
  usePolling(fetchLive, 6000);
  useEffect(() => {
    fetchHistory();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, from, to]);
  useEffect(() => setPage(1), [from, to]);

  return (
    <DashboardLayout title="Operations">
      <p className="text-sm text-gray-500">
        {admin?.role === 'OPERATOR'
          ? 'Your drivers, jeepneys, and live passenger occupancy.'
          : `Fleet-wide view as ${admin ? ROLE_LABELS[admin.role] : ''}: live passenger occupancy and trips.`}
      </p>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}

      {overview ? (
        <>
          <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
            <StatCard label="Active trips" value={overview.activeTrips} icon={<Icon d={ICONS.route} />} />
            <StatCard label="Passengers on board" value={overview.passengersOnBoard} icon={<Icon d={ICONS.people} />} />
            <StatCard label="Nearly full" value={overview.jeepneysNearlyFull} icon={<Icon d={ICONS.bus} />} tone={overview.jeepneysNearlyFull ? 'warning' : 'blue'} />
            <StatCard label="Full" value={overview.jeepneysFull} icon={<Icon d={ICONS.bus} />} tone={overview.jeepneysFull ? 'critical' : 'blue'} />
            <StatCard label="Drivers" value={overview.drivers} icon={<Icon d={ICONS.people} />} />
            <StatCard label="Jeepneys" value={overview.vehicles} icon={<Icon d={ICONS.bus} />} />
            <StatCard label="Open short-tripping reports" value={overview.openIncidents} icon={<Icon d={ICONS.alert} />} tone={overview.openIncidents ? 'warning' : 'blue'} />
            <StatCard label="Active restrictions" value={overview.activeRestrictions} icon={<Icon d={ICONS.block} />} tone={overview.activeRestrictions ? 'critical' : 'blue'} />
          </div>
          {overview.vehiclesMissingCapacity > 0 && (
            <p className="mt-4 rounded-lg bg-status-warning-bg px-4 py-3 text-sm font-medium text-status-warning">
              {overview.vehiclesMissingCapacity} jeepney{overview.vehiclesMissingCapacity === 1 ? ' has' : 's have'} no seating capacity set, so drivers can't start trips with{' '}
              {overview.vehiclesMissingCapacity === 1 ? 'it' : 'them'}. Set it under Fleet → Jeepneys.
            </p>
          )}
        </>
      ) : (
        <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <StatCardSkeleton key={i} />
          ))}
        </div>
      )}

      <Card className="mt-6">
        <SectionHeader icon={<Icon d={ICONS.route} />} title="Active trips — live occupancy" action={<span className="text-xs text-gray-400">updates every few seconds</span>} />
        {active === null && !error && <TableSkeleton columns={9} rows={3} />}
        {active && active.length === 0 && <p className="mt-4 text-sm text-gray-500">No trips are running right now.</p>}
        {active && active.length > 0 && (
          <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
            <table className="w-full min-w-[900px] text-left text-sm">
              <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-4 py-3">Driver</th>
                  <th className="px-4 py-3">Plate</th>
                  <th className="px-4 py-3">Started</th>
                  <th className="px-4 py-3">App</th>
                  <th className="px-4 py-3">Manual</th>
                  <th className="px-4 py-3">Total</th>
                  <th className="px-4 py-3">Capacity</th>
                  <th className="px-4 py-3">Seats left</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {active.map((t) => (
                  <tr key={t.id} onClick={() => setOpenTripId(t.id)} className="cursor-pointer transition hover:bg-gray-50">
                    <td className="px-4 py-3 font-medium text-gray-900">{t.driverName}</td>
                    <td className="px-4 py-3 text-gray-600">{t.plateNumber ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-600">{formatManilaTime(t.startedAt)}</td>
                    <PassengerCells t={t} />
                    <td className="px-4 py-3 tabular-nums text-gray-700">{t.remainingSeats ?? '—'}</td>
                    <td className="px-4 py-3">
                      <OccupancyBadge status={t.occupancyStatus} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card className="mt-6">
        <SectionHeader icon={<Icon d={ICONS.bus} />} title="Completed trips" />
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-xs font-medium text-gray-500">
            From
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="ml-2 rounded-lg border border-border-subtle px-2 py-1.5 text-sm text-gray-700" />
          </label>
          <label className="text-xs font-medium text-gray-500">
            To
            <input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="ml-2 rounded-lg border border-border-subtle px-2 py-1.5 text-sm text-gray-700" />
          </label>
          {(from || to) && (
            <button
              onClick={() => {
                setFrom('');
                setTo('');
              }}
              className={secondaryButton}
            >
              Clear
            </button>
          )}
        </div>
        {history === null && !error && <TableSkeleton columns={9} rows={4} />}
        {history && history.trips.length === 0 && <p className="mt-4 text-sm text-gray-500">No completed trips for this filter.</p>}
        {history && history.trips.length > 0 && (
          <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
            <table className="w-full min-w-[900px] text-left text-sm">
              <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-4 py-3">Date</th>
                  <th className="px-4 py-3">Driver</th>
                  <th className="px-4 py-3">Plate</th>
                  <th className="px-4 py-3">Route</th>
                  <th className="px-4 py-3">App</th>
                  <th className="px-4 py-3">Manual</th>
                  <th className="px-4 py-3">Total carried</th>
                  <th className="px-4 py-3">Capacity</th>
                  <th className="px-4 py-3">Peak on board</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {history.trips.map((t) => (
                  <tr key={t.id} onClick={() => setOpenTripId(t.id)} className="cursor-pointer transition hover:bg-gray-50">
                    <td className="px-4 py-3 text-gray-600">{formatManilaDate(t.startedAt)}</td>
                    <td className="px-4 py-3 font-medium text-gray-900">{t.driverName}</td>
                    <td className="px-4 py-3 text-gray-600">{t.plateNumber ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-600">{t.route ?? '—'}</td>
                    <PassengerCells t={t} />
                    <td className="px-4 py-3 tabular-nums text-gray-700">{t.peakOccupancy}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {history && <PaginationControls currentPage={history.currentPage} totalPages={history.totalPages} hasNextPage={history.currentPage < history.totalPages} onPageChange={setPage} />}
        <p className="mt-3 text-xs text-gray-400">
          "Total carried" counts everyone who boarded during the trip (app + manual). "Peak on board" is the most that were on at once.
        </p>
      </Card>

      {openTripId && <TripDetailModal tripId={openTripId} onClose={() => setOpenTripId(null)} />}
    </DashboardLayout>
  );
}
