import { useEffect, useState, type FormEvent } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { Card, SectionHeader } from '../components/Card';
import { TableSkeleton } from '../components/Skeleton';
import { PaginationControls } from '../components/PaginationControls';
import { Modal, ModalActions } from '../components/Modal';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { formatManilaDateTime } from '../lib/formatDate';
import { canManageFleet, isAdminLevel, useAuth } from '../lib/auth';
import {
  DISCIPLINARY_LABELS,
  DisciplinaryBadge,
  OccupancyBadge,
  OperationalBadge,
  errorMessage,
  inputClass,
  primaryButton,
  secondaryButton,
  type DisciplinaryStatus,
  type Occupancy,
  type OperationalStatus,
  type Restriction,
} from '../lib/ops';

interface VehicleRow {
  id: string;
  plateNumber: string;
  seatingCapacity: number | null;
  operatorId: string | null;
  operatorName: string | null;
  isActive: boolean;
  assignedDrivers: { assignmentId: string; driverId: string; fullName: string }[];
  activeTrip: { id: string; driverName: string } | null;
}
interface VehiclesResponse {
  vehicles: VehicleRow[];
  currentPage: number;
  totalVehicles: number;
  totalPages: number;
}

interface DriverRow {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  isActive: boolean;
  operationalStatus: OperationalStatus;
  disciplinaryStatus: DisciplinaryStatus;
  operatorId: string | null;
  operatorName: string | null;
  vehicles: { assignmentId: string; id: string; plateNumber: string; seatingCapacity: number | null }[];
  activeTrip: { id: string; plateNumber: string | null; occupancy: Occupancy | null } | null;
  restriction: Restriction | null;
}
interface DriversResponse {
  drivers: DriverRow[];
  currentPage: number;
  totalDrivers: number;
  totalPages: number;
}
interface Operator {
  id: string;
  fullName: string;
  email: string;
  isActive: boolean;
}

// ---------------------------------------------------------------- modals

function AddVehicleModal({ operators, onClose, onDone }: { operators: Operator[] | null; onClose: () => void; onDone: () => void }) {
  const { admin } = useAuth();
  const [plate, setPlate] = useState('');
  const [capacity, setCapacity] = useState('');
  const [operatorId, setOperatorId] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.post('/api/admin/ops/vehicles', {
        plateNumber: plate,
        seatingCapacity: capacity.trim() ? Number(capacity) : null,
        ...(operatorId ? { operatorId } : {}),
      });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal title="Add jeepney" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Plate number</label>
          <input required value={plate} onChange={(e) => setPlate(e.target.value)} placeholder="e.g. ABC 1234" className={inputClass} />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Registered seating capacity</label>
          <input type="number" min={1} max={100} value={capacity} onChange={(e) => setCapacity(e.target.value)} placeholder="Number of passengers" className={inputClass} />
          <p className="mt-1.5 text-xs text-gray-400">
            Every jeepney has its own capacity — enter the registered figure. Drivers can't start a trip with a jeepney until this is set. (MANIBELA still needs to confirm
            whether this counts seated passengers only.)
          </p>
        </div>
        {isAdminLevel(admin?.role) && (
          <div>
            <label className="block text-sm font-medium text-gray-700">Operator</label>
            <select value={operatorId} onChange={(e) => setOperatorId(e.target.value)} className={inputClass}>
              <option value="">Unassigned</option>
              {operators?.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.fullName}
                </option>
              ))}
            </select>
          </div>
        )}
        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Add jeepney" submitting={submitting} />
      </form>
    </Modal>
  );
}

function EditVehicleModal({ vehicle, operators, onClose, onDone }: { vehicle: VehicleRow; operators: Operator[] | null; onClose: () => void; onDone: () => void }) {
  const { admin } = useAuth();
  const [capacity, setCapacity] = useState(vehicle.seatingCapacity?.toString() ?? '');
  const [operatorId, setOperatorId] = useState(vehicle.operatorId ?? '');
  const [isActive, setIsActive] = useState(vehicle.isActive);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      const body: Record<string, unknown> = { isActive };
      if (capacity.trim()) body.seatingCapacity = Number(capacity);
      if (isAdminLevel(admin?.role)) body.operatorId = operatorId || null;
      await apiClient.patch(`/api/admin/ops/vehicles/${vehicle.id}`, body);
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal title={`Edit ${vehicle.plateNumber}`} onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Registered seating capacity</label>
          <input type="number" min={1} max={100} required value={capacity} onChange={(e) => setCapacity(e.target.value)} className={inputClass} />
        </div>
        {isAdminLevel(admin?.role) && (
          <div>
            <label className="block text-sm font-medium text-gray-700">Operator</label>
            <select value={operatorId} onChange={(e) => setOperatorId(e.target.value)} className={inputClass}>
              <option value="">Unassigned</option>
              {operators?.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.fullName}
                </option>
              ))}
            </select>
          </div>
        )}
        <label className="flex items-center gap-2 text-sm text-gray-700">
          <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
          Active (uncheck to retire this jeepney)
        </label>
        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Save" submitting={submitting} />
      </form>
    </Modal>
  );
}

/** Assign either a jeepney to a driver, or a driver to a jeepney. */
function AssignModal({
  mode,
  target,
  onClose,
  onDone,
}: {
  mode: 'vehicle-for-driver' | 'driver-for-vehicle';
  target: { id: string; label: string; alreadyIds: string[] };
  onClose: () => void;
  onDone: () => void;
}) {
  const [options, setOptions] = useState<{ id: string; label: string }[] | null>(null);
  const [choice, setChoice] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const path = mode === 'vehicle-for-driver' ? '/api/admin/ops/vehicles?pageSize=100' : '/api/admin/ops/drivers?pageSize=100';
    apiClient
      .get<{ vehicles?: VehicleRow[]; drivers?: DriverRow[] }>(path)
      .then((res) => {
        const list =
          mode === 'vehicle-for-driver'
            ? (res.vehicles ?? []).filter((v) => v.isActive).map((v) => ({ id: v.id, label: `${v.plateNumber}${v.seatingCapacity ? ` (${v.seatingCapacity} seats)` : ' (capacity not set)'}` }))
            : (res.drivers ?? []).map((d) => ({ id: d.id, label: `${d.fullName} (${d.driverId})` }));
        setOptions(list.filter((o) => !target.alreadyIds.includes(o.id)));
      })
      .catch((err) => setError(errorMessage(err, 'Could not load the list.')));
  }, [mode, target.alreadyIds]);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!choice || submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.post('/api/admin/ops/assignments', mode === 'vehicle-for-driver' ? { driverId: target.id, vehicleId: choice } : { driverId: choice, vehicleId: target.id });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal title={mode === 'vehicle-for-driver' ? 'Assign a jeepney' : 'Assign a driver'} subtitle={target.label} onClose={onClose}>
      <form onSubmit={submit}>
        {!options && !error && <p className="text-sm text-gray-500">Loading...</p>}
        {options && options.length === 0 && <p className="text-sm text-gray-500">Nothing available to assign.</p>}
        {options && options.length > 0 && (
          <select value={choice} onChange={(e) => setChoice(e.target.value)} className={inputClass} required>
            <option value="">Select…</option>
            {options.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </select>
        )}
        <p className="mt-2 text-xs text-gray-400">A driver can have several jeepneys, and chooses which one they're driving before each trip.</p>
        {error && <p className="mt-3 text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Assign" submitting={submitting} disabled={!choice} />
      </form>
    </Modal>
  );
}

function StatusModal({ driver, onClose, onDone }: { driver: DriverRow; onClose: () => void; onDone: () => void }) {
  const [operational, setOperational] = useState<OperationalStatus>(driver.operationalStatus);
  const [disciplinary, setDisciplinary] = useState<DisciplinaryStatus>(driver.disciplinaryStatus);
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const changed = operational !== driver.operationalStatus || disciplinary !== driver.disciplinaryStatus;
  const needsNote = disciplinary !== 'NONE' && disciplinary !== driver.disciplinaryStatus;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!changed || submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.patch(`/api/admin/ops/drivers/${driver.id}/status`, {
        ...(operational !== driver.operationalStatus ? { operationalStatus: operational } : {}),
        ...(disciplinary !== driver.disciplinaryStatus ? { disciplinaryStatus: disciplinary } : {}),
        ...(note.trim() ? { note: note.trim() } : {}),
      });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Modal title="Driver status" subtitle={driver.fullName} onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Operating status</label>
          <select value={operational} onChange={(e) => setOperational(e.target.value as OperationalStatus)} className={inputClass}>
            <option value="ACTIVE">Active</option>
            <option value="INACTIVE">Inactive</option>
          </select>
          <p className="mt-1.5 text-xs text-gray-400">Inactive means the driver isn't operating (for example, stopped driving). It is not a sanction.</p>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">Disciplinary status</label>
          <select value={disciplinary} onChange={(e) => setDisciplinary(e.target.value as DisciplinaryStatus)} className={inputClass}>
            {(Object.keys(DISCIPLINARY_LABELS) as DisciplinaryStatus[]).map((s) => (
              <option key={s} value={s}>
                {DISCIPLINARY_LABELS[s]}
              </option>
            ))}
          </select>
          <p className="mt-1.5 text-xs text-gray-400">
            Only apply approved disciplinary actions. Complaints never change this automatically. A suspended driver cannot start trips.
          </p>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700">
            Reason / note {needsNote && <span className="text-brand-red">(required)</span>}
          </label>
          <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3} className={inputClass} required={needsNote} />
        </div>
        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Save status" submitting={submitting} disabled={!changed} />
      </form>
    </Modal>
  );
}

function LiftModal({ restriction, driverName, onClose, onDone }: { restriction: Restriction; driverName: string; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError(null);
    try {
      await apiClient.post(`/api/admin/ops/restrictions/${restriction.id}/lift`, { note });
      onDone();
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }
  return (
    <Modal title="Lift restriction" subtitle={`${driverName} — expires ${formatManilaDateTime(restriction.expiresAt)}`} onClose={onClose}>
      <form onSubmit={submit}>
        <label className="block text-sm font-medium text-gray-700">Why is it being lifted? (recorded)</label>
        <textarea required minLength={3} value={note} onChange={(e) => setNote(e.target.value)} rows={3} className={inputClass} />
        {error && <p className="mt-3 text-sm font-medium text-brand-red">{error}</p>}
        <ModalActions onCancel={onClose} submitLabel="Lift restriction" submitting={submitting} />
      </form>
    </Modal>
  );
}

// ---------------------------------------------------------------- tabs

function JeepneysTab({ operators }: { operators: Operator[] | null }) {
  const { admin } = useAuth();
  const canWrite = canManageFleet(admin?.role);
  const [data, setData] = useState<VehiclesResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const debounced = useDebouncedValue(search, 300);
  const [missingOnly, setMissingOnly] = useState(false);
  const [page, setPage] = useState(1);
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<VehicleRow | null>(null);
  const [assigning, setAssigning] = useState<VehicleRow | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  function load() {
    const params = new URLSearchParams({ page: String(page), pageSize: '25' });
    if (debounced.trim()) params.set('search', debounced.trim());
    if (missingOnly) params.set('missingCapacity', '1');
    apiClient
      .get<VehiclesResponse>(`/api/admin/ops/vehicles?${params.toString()}`)
      .then((r) => {
        setData(r);
        setError(null);
      })
      .catch((e) => setError(errorMessage(e, 'Could not load jeepneys.')));
  }
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debounced, missingOnly, page]);
  useEffect(() => setPage(1), [debounced, missingOnly]);
  usePolling(load, 10_000);

  async function unassign(assignmentId: string) {
    setActionError(null);
    try {
      await apiClient.delete(`/api/admin/ops/assignments/${assignmentId}`);
      load();
    } catch (err) {
      setActionError(errorMessage(err));
    }
  }

  return (
    <Card className="mt-4">
      <SectionHeader
        icon={<span className="text-xs font-bold">🚌</span>}
        title="Jeepneys & seating capacity"
        action={
          canWrite && (
            <button onClick={() => setAdding(true)} className={primaryButton}>
              Add jeepney
            </button>
          )
        }
      />
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search plate number" className="w-56 rounded-lg border border-border-subtle bg-white px-3 py-2 text-sm focus:border-brand-blue focus:outline-none" />
        <label className="flex items-center gap-2 text-sm text-gray-600">
          <input type="checkbox" checked={missingOnly} onChange={(e) => setMissingOnly(e.target.checked)} />
          Only missing capacity
        </label>
      </div>
      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {actionError && <p className="mt-4 text-sm font-medium text-brand-red">{actionError}</p>}
      {!data && !error && <TableSkeleton columns={6} />}
      {data && data.vehicles.length === 0 && <p className="mt-4 text-sm text-gray-500">No jeepneys found.{canWrite && ' Add one to get started.'}</p>}
      {data && data.vehicles.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[880px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">Plate</th>
                <th className="px-4 py-3">Seating capacity</th>
                <th className="px-4 py-3">Operator</th>
                <th className="px-4 py-3">Assigned drivers</th>
                <th className="px-4 py-3">Status</th>
                {canWrite && <th className="px-4 py-3">Actions</th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {data.vehicles.map((v) => (
                <tr key={v.id} className={v.isActive ? '' : 'opacity-60'}>
                  <td className="px-4 py-3 font-semibold text-gray-900">{v.plateNumber}</td>
                  <td className="px-4 py-3">
                    {v.seatingCapacity ? (
                      <span className="tabular-nums text-gray-800">{v.seatingCapacity}</span>
                    ) : (
                      <span className="rounded-full bg-status-warning-bg px-2.5 py-0.5 text-xs font-semibold text-status-warning">Not set</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{v.operatorName ?? '—'}</td>
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap gap-1.5">
                      {v.assignedDrivers.length === 0 && <span className="text-gray-400">None</span>}
                      {v.assignedDrivers.map((d) => (
                        <span key={d.assignmentId} className="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-700">
                          {d.fullName}
                          {canWrite && (
                            <button onClick={() => unassign(d.assignmentId)} className="text-gray-400 hover:text-brand-red" aria-label={`Remove ${d.fullName}`} title="Remove assignment">
                              ×
                            </button>
                          )}
                        </span>
                      ))}
                    </div>
                  </td>
                  <td className="px-4 py-3 text-xs">
                    {!v.isActive ? <span className="text-gray-500">Retired</span> : v.activeTrip ? <span className="font-semibold text-status-good">On trip — {v.activeTrip.driverName}</span> : <span className="text-gray-500">Idle</span>}
                  </td>
                  {canWrite && (
                    <td className="px-4 py-3">
                      <div className="flex gap-1.5">
                        <button onClick={() => setEditing(v)} className={secondaryButton}>
                          Edit
                        </button>
                        <button onClick={() => setAssigning(v)} disabled={!v.isActive} className={secondaryButton}>
                          Assign driver
                        </button>
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {data && <PaginationControls currentPage={data.currentPage} totalPages={data.totalPages} hasNextPage={data.currentPage < data.totalPages} onPageChange={setPage} />}

      {adding && (
        <AddVehicleModal
          operators={operators}
          onClose={() => setAdding(false)}
          onDone={() => {
            setAdding(false);
            load();
          }}
        />
      )}
      {editing && (
        <EditVehicleModal
          vehicle={editing}
          operators={operators}
          onClose={() => setEditing(null)}
          onDone={() => {
            setEditing(null);
            load();
          }}
        />
      )}
      {assigning && (
        <AssignModal
          mode="driver-for-vehicle"
          target={{ id: assigning.id, label: assigning.plateNumber, alreadyIds: assigning.assignedDrivers.map((d) => d.driverId) }}
          onClose={() => setAssigning(null)}
          onDone={() => {
            setAssigning(null);
            load();
          }}
        />
      )}
    </Card>
  );
}

function DriversTab({ operators }: { operators: Operator[] | null }) {
  const { admin } = useAuth();
  const canWrite = canManageFleet(admin?.role);
  const adminLevel = isAdminLevel(admin?.role);
  const [data, setData] = useState<DriversResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const debounced = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [assigning, setAssigning] = useState<DriverRow | null>(null);
  const [statusFor, setStatusFor] = useState<DriverRow | null>(null);
  const [lifting, setLifting] = useState<DriverRow | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  function load() {
    const params = new URLSearchParams({ page: String(page), pageSize: '25' });
    if (debounced.trim()) params.set('search', debounced.trim());
    apiClient
      .get<DriversResponse>(`/api/admin/ops/drivers?${params.toString()}`)
      .then((r) => {
        setData(r);
        setError(null);
      })
      .catch((e) => setError(errorMessage(e, 'Could not load drivers.')));
  }
  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debounced, page]);
  useEffect(() => setPage(1), [debounced]);
  usePolling(load, 10_000);

  async function unassign(assignmentId: string) {
    setActionError(null);
    try {
      await apiClient.delete(`/api/admin/ops/assignments/${assignmentId}`);
      load();
    } catch (err) {
      setActionError(errorMessage(err));
    }
  }

  async function setOperator(driverId: string, operatorId: string) {
    setActionError(null);
    try {
      await apiClient.patch(`/api/admin/ops/drivers/${driverId}/operator`, { operatorId: operatorId || null });
      load();
    } catch (err) {
      setActionError(errorMessage(err));
    }
  }

  return (
    <Card className="mt-4">
      <SectionHeader icon={<span className="text-xs font-bold">👤</span>} title="Drivers, assignments & status" />
      <div className="mt-3">
        <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, driver ID, or plate" className="w-72 rounded-lg border border-border-subtle bg-white px-3 py-2 text-sm focus:border-brand-blue focus:outline-none" />
      </div>
      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {actionError && <p className="mt-4 text-sm font-medium text-brand-red">{actionError}</p>}
      {!data && !error && <TableSkeleton columns={6} />}
      {data && data.drivers.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">{adminLevel ? 'No drivers found.' : 'No drivers are assigned to you yet. Ask an administrator to assign drivers to your operator account.'}</p>
      )}
      {data && data.drivers.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[1080px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">Driver</th>
                {adminLevel && <th className="px-4 py-3">Operator</th>}
                <th className="px-4 py-3">Jeepneys</th>
                <th className="px-4 py-3">Operating</th>
                <th className="px-4 py-3">Disciplinary</th>
                <th className="px-4 py-3">Current trip</th>
                <th className="px-4 py-3">Trip-start restriction</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {data.drivers.map((d) => (
                <tr key={d.id}>
                  <td className="px-4 py-3">
                    <p className="font-medium text-gray-900">{d.fullName}</p>
                    <p className="text-xs text-gray-500">{d.driverId}</p>
                    {!d.isActive && <p className="text-xs font-semibold text-status-critical">Login deactivated</p>}
                  </td>
                  {adminLevel && (
                    <td className="px-4 py-3">
                      <select value={d.operatorId ?? ''} onChange={(e) => setOperator(d.id, e.target.value)} className="rounded-lg border border-border-subtle bg-white px-2 py-1.5 text-xs">
                        <option value="">Unassigned</option>
                        {operators?.map((o) => (
                          <option key={o.id} value={o.id}>
                            {o.fullName}
                          </option>
                        ))}
                      </select>
                    </td>
                  )}
                  <td className="px-4 py-3">
                    <div className="flex flex-wrap items-center gap-1.5">
                      {d.vehicles.length === 0 && <span className="text-gray-400">None</span>}
                      {d.vehicles.map((v) => (
                        <span key={v.assignmentId} className="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-700">
                          {v.plateNumber}
                          <span className="text-gray-400">· {v.seatingCapacity ?? '?'}</span>
                          {canWrite && (
                            <button onClick={() => unassign(v.assignmentId)} className="text-gray-400 hover:text-brand-red" aria-label={`Remove ${v.plateNumber}`} title="Remove assignment">
                              ×
                            </button>
                          )}
                        </span>
                      ))}
                      {canWrite && (
                        <button onClick={() => setAssigning(d)} className="rounded-full border border-dashed border-gray-300 px-2.5 py-0.5 text-xs font-semibold text-gray-500 hover:border-brand-blue hover:text-brand-blue">
                          + Assign
                        </button>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <OperationalBadge status={d.operationalStatus} />
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <DisciplinaryBadge status={d.disciplinaryStatus} />
                      {canWrite && (
                        <button onClick={() => setStatusFor(d)} className="text-xs font-semibold text-brand-blue-dark hover:underline">
                          Change
                        </button>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    {d.activeTrip ? (
                      <div className="space-y-1">
                        <p className="text-xs font-semibold text-gray-800">{d.activeTrip.plateNumber}</p>
                        <p className="text-xs text-gray-500">
                          {d.activeTrip.occupancy ? `${d.activeTrip.occupancy.totalPassengers}/${d.activeTrip.occupancy.seatingCapacity ?? '?'} on board` : ''}
                        </p>
                        <OccupancyBadge status={d.activeTrip.occupancy?.status ?? null} />
                      </div>
                    ) : (
                      <span className="text-gray-400">Not driving</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    {d.restriction ? (
                      <div className="space-y-1">
                        <p className="text-xs font-semibold text-status-critical">Until {formatManilaDateTime(d.restriction.expiresAt)}</p>
                        {canWrite && (
                          <button onClick={() => setLifting(d)} className="text-xs font-semibold text-brand-blue-dark hover:underline">
                            Lift
                          </button>
                        )}
                      </div>
                    ) : (
                      <span className="text-gray-400">None</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {data && <PaginationControls currentPage={data.currentPage} totalPages={data.totalPages} hasNextPage={data.currentPage < data.totalPages} onPageChange={setPage} />}

      {assigning && (
        <AssignModal
          mode="vehicle-for-driver"
          target={{ id: assigning.id, label: assigning.fullName, alreadyIds: assigning.vehicles.map((v) => v.id) }}
          onClose={() => setAssigning(null)}
          onDone={() => {
            setAssigning(null);
            load();
          }}
        />
      )}
      {statusFor && (
        <StatusModal
          driver={statusFor}
          onClose={() => setStatusFor(null)}
          onDone={() => {
            setStatusFor(null);
            load();
          }}
        />
      )}
      {lifting?.restriction && (
        <LiftModal
          restriction={lifting.restriction}
          driverName={lifting.fullName}
          onClose={() => setLifting(null)}
          onDone={() => {
            setLifting(null);
            load();
          }}
        />
      )}
    </Card>
  );
}

export default function FleetPage() {
  const { admin } = useAuth();
  const [tab, setTab] = useState<'jeepneys' | 'drivers'>('jeepneys');
  const [operators, setOperators] = useState<Operator[] | null>(null);

  useEffect(() => {
    if (!isAdminLevel(admin?.role)) return;
    apiClient
      .get<{ operators: Operator[] }>('/api/admin/ops/operators')
      .then((r) => setOperators(r.operators))
      .catch(() => setOperators([]));
  }, [admin?.role]);

  return (
    <DashboardLayout title="Fleet">
      <p className="text-sm text-gray-500">
        Register jeepneys and their seating capacity, decide which drivers may drive which jeepney, and manage driver status.
        {admin?.role === 'MANIBELA' && ' (View only.)'}
      </p>
      <div className="mt-4 flex gap-2">
        {(['jeepneys', 'drivers'] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`rounded-lg px-3.5 py-2 text-sm font-semibold transition ${tab === t ? 'bg-brand-blue text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}
          >
            {t === 'jeepneys' ? 'Jeepneys' : 'Drivers'}
          </button>
        ))}
      </div>
      {tab === 'jeepneys' ? <JeepneysTab operators={operators} /> : <DriversTab operators={operators} />}
    </DashboardLayout>
  );
}
