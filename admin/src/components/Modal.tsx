import type { ReactNode } from 'react';

/** Centered dialog with a dimmed backdrop — same look as the confirm/reset
 * dialogs elsewhere in the admin, shared so the new fleet pages don't each
 * re-implement it. */
export function Modal({
  title,
  subtitle,
  onClose,
  children,
  wide = false,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  children: ReactNode;
  wide?: boolean;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />
      <div
        className={`relative max-h-[90vh] w-full overflow-y-auto rounded-2xl bg-white p-6 shadow-xl ${
          wide ? 'max-w-2xl' : 'max-w-md'
        }`}
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 className="font-display text-base font-semibold text-gray-900">{title}</h2>
            {subtitle && <p className="mt-1 text-sm text-gray-500">{subtitle}</p>}
          </div>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100" aria-label="Close">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
              <path d="M5 5l14 14M19 5 5 19" />
            </svg>
          </button>
        </div>
        <div className="mt-4">{children}</div>
      </div>
    </div>
  );
}

export function ModalActions({
  onCancel,
  submitLabel,
  submitting,
  danger = false,
  disabled = false,
}: {
  onCancel: () => void;
  submitLabel: string;
  submitting: boolean;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <div className="mt-5 flex gap-2">
      <button
        type="submit"
        disabled={submitting || disabled}
        className={`flex-1 rounded-lg px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60 ${
          danger ? 'bg-status-critical' : 'bg-brand-blue'
        }`}
      >
        {submitting ? 'Saving...' : submitLabel}
      </button>
      <button
        type="button"
        onClick={onCancel}
        className="flex-1 rounded-lg border border-border-subtle px-4 py-2.5 text-sm font-semibold text-gray-600 hover:bg-gray-50"
      >
        Cancel
      </button>
    </div>
  );
}
