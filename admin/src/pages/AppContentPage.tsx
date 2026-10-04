import { useEffect, useState, type FormEvent } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { Card, SectionHeader } from '../components/Card';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { apiClient, ApiError } from '../lib/apiClient';

// Lists the commuter app reads live — see GET /api/commuter/id-types and
// /api/commuter/hotlines. Nothing here is baked into the app.

interface IdType {
  id: string;
  label: string;
  hasExpiry: boolean;
  active: boolean;
}

interface Hotline {
  id: string;
  name: string;
  number: string;
  description: string;
  category: string;
  active: boolean;
}

const CATEGORIES = [
  { value: 'emergency', label: 'General emergency' },
  { value: 'police', label: 'Police' },
  { value: 'fire', label: 'Fire' },
  { value: 'medical', label: 'Medical / ambulance' },
  { value: 'transport', label: 'Transport (LTFRB, etc.)' },
  { value: 'other', label: 'Other' },
];

const INPUT =
  'mt-1.5 w-full rounded-lg border border-border-subtle bg-white px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none';

function IdIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="9" cy="11" r="2" />
      <path d="M6.5 16c.5-1.5 1.5-2 2.5-2s2 .5 2.5 2M14 10h4M14 13h3" strokeLinecap="round" />
    </svg>
  );
}

function PhoneIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path
        d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"
        strokeLinejoin="round"
      />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M4 7h16M9 7V4h6v3M6.5 7l1 13h9l1-13M10 11v6M14 11v6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function ActiveBadge({ active }: { active: boolean }) {
  return (
    <span
      className={`inline-flex rounded-full px-2.5 py-0.5 text-xs font-semibold ${
        active ? 'bg-status-good-bg text-status-good' : 'bg-gray-100 text-gray-500'
      }`}
    >
      {active ? 'Shown in app' : 'Hidden'}
    </span>
  );
}

function errorText(err: unknown): string {
  return err instanceof ApiError ? err.message : 'Something went wrong. Please try again.';
}

function RowActions({ onEdit, onDelete }: { onEdit: () => void; onDelete: () => void }) {
  return (
    <div className="flex gap-1.5">
      <button
        onClick={onEdit}
        className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
      >
        Edit
      </button>
      <button
        onClick={onDelete}
        className="rounded-lg border border-status-critical px-2.5 py-1 text-xs font-semibold text-status-critical hover:bg-status-critical-bg"
      >
        Delete
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// GOVERNMENT IDS
// ---------------------------------------------------------------------------

function IdTypeForm({
  initial,
  onSaved,
  onCancel,
}: {
  initial: IdType | null;
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [label, setLabel] = useState(initial?.label ?? '');
  const [hasExpiry, setHasExpiry] = useState(initial?.hasExpiry ?? true);
  const [active, setActive] = useState(initial?.active ?? true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;
    if (!label.trim()) {
      setError('Enter a name for this ID.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      const body = { label, hasExpiry, active };
      if (initial) await apiClient.patch(`/api/admin/id-types/${initial.id}`, body);
      else await apiClient.post('/api/admin/id-types', body);
      onSaved();
    } catch (err) {
      setError(errorText(err));
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 max-w-md space-y-4 rounded-lg border border-border-subtle bg-gray-50 p-4">
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="idTypeLabel">
          ID name
        </label>
        <input
          id="idTypeLabel"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          maxLength={80}
          placeholder="e.g. UMID"
          className={INPUT}
        />
      </div>
      <label className="flex items-start gap-2 text-sm text-gray-700">
        <input type="checkbox" checked={hasExpiry} onChange={(e) => setHasExpiry(e.target.checked)} className="mt-0.5" />
        <span>
          This ID prints an expiry date
          <span className="block text-xs text-gray-500">
            Expired IDs are rejected, and an unreadable expiry date sends the account to manual review.
          </span>
        </span>
      </label>
      <label className="flex items-center gap-2 text-sm text-gray-700">
        <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
        Show in the app
      </label>
      {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-50"
        >
          {isSubmitting ? 'Saving...' : initial ? 'Save Changes' : 'Add ID'}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-lg border border-border-subtle px-4 py-2.5 text-sm font-semibold text-gray-600 hover:bg-white"
        >
          Cancel
        </button>
      </div>
    </form>
  );
}

function IdTypesSection() {
  const [idTypes, setIdTypes] = useState<IdType[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  // `undefined` = form closed, `null` = adding, an IdType = editing it.
  const [editing, setEditing] = useState<IdType | null | undefined>(undefined);
  const [deleteTarget, setDeleteTarget] = useState<IdType | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  function load() {
    apiClient
      .get<{ idTypes: IdType[] }>('/api/admin/id-types')
      .then((res) => {
        setIdTypes(res.idTypes);
        setError(null);
      })
      .catch((err) => setError(errorText(err)));
  }
  useEffect(load, []);

  async function confirmDelete() {
    if (!deleteTarget) return;
    setIsDeleting(true);
    try {
      await apiClient.delete(`/api/admin/id-types/${deleteTarget.id}`);
      setDeleteTarget(null);
      load();
    } catch (err) {
      setError(errorText(err));
      setDeleteTarget(null);
    } finally {
      setIsDeleting(false);
    }
  }

  return (
    <Card>
      <SectionHeader
        icon={<IdIcon />}
        title="Government IDs"
        action={
          editing === undefined && (
            <button
              onClick={() => setEditing(null)}
              className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110"
            >
              Add ID
            </button>
          )
        }
      />
      <p className="mt-1 pl-9 text-sm text-gray-500">
        The ID types commuters can pick when verifying their account. Changes appear in the app right away.
      </p>

      {editing !== undefined && (
        <IdTypeForm
          key={editing?.id ?? 'new'}
          initial={editing}
          onSaved={() => {
            setEditing(undefined);
            load();
          }}
          onCancel={() => setEditing(undefined)}
        />
      )}

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!idTypes && !error && <div className="mt-4 h-24 animate-pulse rounded-lg bg-gray-100" />}
      {idTypes && idTypes.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">
          No ID types yet — commuters can't finish verification until you add at least one.
        </p>
      )}
      {idTypes && idTypes.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[560px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">ID Name</th>
                <th className="px-4 py-3">Expiry Date</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {idTypes.map((t) => (
                <tr key={t.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{t.label}</td>
                  <td className="px-4 py-3 text-gray-600">{t.hasExpiry ? 'Checked' : 'Not applicable'}</td>
                  <td className="px-4 py-3">
                    <ActiveBadge active={t.active} />
                  </td>
                  <td className="px-4 py-3">
                    <RowActions onEdit={() => setEditing(t)} onDelete={() => setDeleteTarget(t)} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {deleteTarget && (
        <ConfirmDialog
          icon={<TrashIcon />}
          tone="danger"
          title="Delete this ID type?"
          message={`"${deleteTarget.label}" will no longer be offered to commuters. Accounts that already used it keep it on record.`}
          confirmLabel="Delete"
          isSubmitting={isDeleting}
          onConfirm={confirmDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      )}
    </Card>
  );
}

// ---------------------------------------------------------------------------
// EMERGENCY HOTLINES
// ---------------------------------------------------------------------------

function HotlineForm({
  initial,
  onSaved,
  onCancel,
}: {
  initial: Hotline | null;
  onSaved: () => void;
  onCancel: () => void;
}) {
  const [name, setName] = useState(initial?.name ?? '');
  const [number, setNumber] = useState(initial?.number ?? '');
  const [description, setDescription] = useState(initial?.description ?? '');
  const [category, setCategory] = useState(initial?.category ?? 'other');
  const [active, setActive] = useState(initial?.active ?? true);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;
    if (!name.trim() || !number.trim()) {
      setError('Enter a name and a number.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      const body = { name, number, description, category, active };
      if (initial) await apiClient.patch(`/api/admin/hotlines/${initial.id}`, body);
      else await apiClient.post('/api/admin/hotlines', body);
      onSaved();
    } catch (err) {
      setError(errorText(err));
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 max-w-md space-y-4 rounded-lg border border-border-subtle bg-gray-50 p-4">
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="hotlineName">
          Name
        </label>
        <input
          id="hotlineName"
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={80}
          placeholder="e.g. Philippine National Police"
          className={INPUT}
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="hotlineNumber">
          Number
        </label>
        <input
          id="hotlineNumber"
          value={number}
          onChange={(e) => setNumber(e.target.value)}
          maxLength={30}
          inputMode="tel"
          placeholder="e.g. 117 or (02) 8426-0219"
          className={INPUT}
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="hotlineDescription">
          Description <span className="font-normal text-gray-400">(optional)</span>
        </label>
        <input
          id="hotlineDescription"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          maxLength={200}
          placeholder="What this line is for"
          className={INPUT}
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="hotlineCategory">
          Icon
        </label>
        <select id="hotlineCategory" value={category} onChange={(e) => setCategory(e.target.value)} className={INPUT}>
          {CATEGORIES.map((c) => (
            <option key={c.value} value={c.value}>
              {c.label}
            </option>
          ))}
        </select>
      </div>
      <label className="flex items-center gap-2 text-sm text-gray-700">
        <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} />
        Show in the app
      </label>
      {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-50"
        >
          {isSubmitting ? 'Saving...' : initial ? 'Save Changes' : 'Add Hotline'}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-lg border border-border-subtle px-4 py-2.5 text-sm font-semibold text-gray-600 hover:bg-white"
        >
          Cancel
        </button>
      </div>
    </form>
  );
}

function HotlinesSection() {
  const [hotlines, setHotlines] = useState<Hotline[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Hotline | null | undefined>(undefined);
  const [deleteTarget, setDeleteTarget] = useState<Hotline | null>(null);
  const [isDeleting, setIsDeleting] = useState(false);

  function load() {
    apiClient
      .get<{ hotlines: Hotline[] }>('/api/admin/hotlines')
      .then((res) => {
        setHotlines(res.hotlines);
        setError(null);
      })
      .catch((err) => setError(errorText(err)));
  }
  useEffect(load, []);

  async function confirmDelete() {
    if (!deleteTarget) return;
    setIsDeleting(true);
    try {
      await apiClient.delete(`/api/admin/hotlines/${deleteTarget.id}`);
      setDeleteTarget(null);
      load();
    } catch (err) {
      setError(errorText(err));
      setDeleteTarget(null);
    } finally {
      setIsDeleting(false);
    }
  }

  return (
    <Card className="mt-6">
      <SectionHeader
        icon={<PhoneIcon />}
        title="Emergency Hotlines"
        action={
          editing === undefined && (
            <button
              onClick={() => setEditing(null)}
              className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110"
            >
              Add Hotline
            </button>
          )
        }
      />
      <p className="mt-1 pl-9 text-sm text-gray-500">
        The numbers shown on the commuter app's Emergency Hotlines screen. Changes appear in the app right away.
      </p>

      {editing !== undefined && (
        <HotlineForm
          key={editing?.id ?? 'new'}
          initial={editing}
          onSaved={() => {
            setEditing(undefined);
            load();
          }}
          onCancel={() => setEditing(undefined)}
        />
      )}

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!hotlines && !error && <div className="mt-4 h-24 animate-pulse rounded-lg bg-gray-100" />}
      {hotlines && hotlines.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">No hotlines yet. Commuters will see an empty list.</p>
      )}
      {hotlines && hotlines.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3">Number</th>
                <th className="px-4 py-3">Description</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {hotlines.map((h) => (
                <tr key={h.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">{h.name}</td>
                  <td className="px-4 py-3 text-gray-900">{h.number}</td>
                  <td className="px-4 py-3 text-gray-600">{h.description || '—'}</td>
                  <td className="px-4 py-3">
                    <ActiveBadge active={h.active} />
                  </td>
                  <td className="px-4 py-3">
                    <RowActions onEdit={() => setEditing(h)} onDelete={() => setDeleteTarget(h)} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {deleteTarget && (
        <ConfirmDialog
          icon={<TrashIcon />}
          tone="danger"
          title="Delete this hotline?"
          message={`"${deleteTarget.name}" (${deleteTarget.number}) will be removed from the commuter app.`}
          confirmLabel="Delete"
          isSubmitting={isDeleting}
          onConfirm={confirmDelete}
          onCancel={() => setDeleteTarget(null)}
        />
      )}
    </Card>
  );
}

export default function AppContentPage() {
  return (
    <DashboardLayout title="IDs & Hotlines">
      <p className="text-sm text-gray-500">Manage the lists shown in the commuter app.</p>
      <div className="mt-6">
        <IdTypesSection />
        <HotlinesSection />
      </div>
    </DashboardLayout>
  );
}
