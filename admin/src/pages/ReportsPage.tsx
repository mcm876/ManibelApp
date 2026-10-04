import { useEffect, useMemo, useState } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { Card, SectionHeader } from '../components/Card';
import { StatCardSkeleton, TableSkeleton } from '../components/Skeleton';
import { MoneyTrendChart, type MoneyPoint } from '../components/MoneyTrendChart';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { manilaDateRangeForCustom } from '../lib/formatDate';
import { formatPhone } from '../lib/formatPhone';
import {
  addTitleBlock,
  addSectionHeader,
  addTable,
  addNote,
  downloadCsv,
  formatManilaDate,
  formatManilaTime,
  money,
  type ColumnSpec,
  type CsvRows,
} from '../lib/csvExport';

interface PerDriverRow {
  driverId: string;
  driverName: string;
  plateNumber: string;
  earnings: number;
  fuelExpense: number;
  otherExpenses: number;
  netIncome: number;
  daysLogged: number;
}

interface OperationsReport {
  totalEarnings: number;
  totalFuelExpense: number;
  totalOtherExpenses: number;
  netIncome: number;
  totalTrips: number;
  daysWithLogs: number;
  series: MoneyPoint[];
  perDriver: PerDriverRow[];
}

interface OperationsDailyRow {
  date: string;
  earnings: number;
  fuelExpense: number;
  otherExpenses: number;
  totalExpenses: number;
  netIncome: number;
  trips: number;
}

interface OperationsPerDriverExportRow {
  driverId: string;
  driverName: string;
  plateNumber: string;
  earnings: number;
  fuelExpense: number;
  otherExpenses: number;
  netIncome: number;
  trips: number;
  daysLogged: number;
}

interface OperationsReportExport {
  reportPeriodLabel: string;
  summary: {
    totalEarnings: number;
    totalFuelExpense: number;
    totalOtherExpenses: number;
    totalExpenses: number;
    netIncome: number;
    totalTrips: number;
    daysWithLogs: number;
  };
  daily: OperationsDailyRow[];
  perDriver: OperationsPerDriverExportRow[];
}

interface DriverExportRow {
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  route: string | null;
  licenseVerified: boolean;
  dateOfBirth: string | null;
  isActive: boolean;
  createdAt: string;
  totalTrips: number;
  completedTrips: number;
}

interface CommuterExportRow {
  commuterId: string;
  fullName: string;
  mobileNumber: string;
  dateOfBirth: string | null;
  phoneVerified: boolean;
  verificationStatus: string | null;
  isActive: boolean;
  createdAt: string;
  totalTrips: number;
}

interface TripExportRow {
  driverName: string;
  plateNumber: string;
  route: string | null;
  status: string;
  startedAt: string;
  endedAt: string | null;
  isShortTrip: boolean;
}

interface ComplaintExportRow {
  id: string;
  complainantName: string;
  driverName: string;
  plateNumber: string;
  route: string | null;
  complaintType: string;
  description: string;
  status: string;
  resolution: string | null;
  resolvedAt: string | null;
  createdAt: string;
}

interface DriverExportSummary {
  totalDrivers: number;
  activeDrivers: number;
  inactiveDrivers: number;
}

interface CommuterExportSummary {
  totalCommuters: number;
  activeCommuters: number;
  inactiveCommuters: number;
  phoneVerified: number;
  pendingVerification: number;
  approvedVerification: number;
  rejectedVerification: number;
}

interface TripExportSummary {
  totalTrips: number;
  completedTrips: number;
  activeTrips: number;
  shortTripsFlagged: number;
  reviewPending: number;
  reviewValid: number;
  reviewInvalid: number;
}

interface ComplaintExportSummary {
  totalComplaints: number;
  pending: number;
  investigating: number;
  resolved: number;
  rejected: number;
}

function formatPeso(n: number): string {
  return `₱${Math.round(n).toLocaleString('en-PH')}`;
}

/** "August 14, 2026" — the exported reports' own "Generated" line, spelled
 * out in full rather than the abbreviated "Aug 14, 2026" the rest of this
 * site's on-screen dates use, matching the format the report spec asks for.
 * Pinned to Asia/Manila explicitly, like every other date on this site
 * (see formatDate.ts) — otherwise this would render in the admin's own
 * browser timezone, showing a different "Generated" date to an admin
 * opening the site from outside PH. */
function formatLongDate(date: Date): string {
  return date.toLocaleDateString('en-PH', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'Asia/Manila' });
}

/** "2026-08-14" — for filenames, timezone-naive (local calendar date). */
function isoDate(date: Date): string {
  const year = date.getFullYear().toString().padStart(4, '0');
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function sumBy<T>(items: T[], get: (item: T) => number): number {
  return items.reduce((total, item) => total + get(item), 0);
}

/** 0 instead of Infinity/NaN when there's nothing to divide by yet (a
 * period with no logged days, or no trips at all). */
function safeDivide(numerator: number, denominator: number): number {
  return denominator > 0 ? numerator / denominator : 0;
}

/** "0917 123 4567" - the admin-facing 09171234567 with spaces added, so a
 * spreadsheet keeps it as text instead of reading the whole thing as a
 * number and dropping the leading 0. */
function formatPhoneForCsv(mobileNumber: string): string {
  const local = formatPhone(mobileNumber);
  return /^\d{11}$/.test(local) ? `${local.slice(0, 4)} ${local.slice(4, 7)} ${local.slice(7)}` : local;
}

/** "PENDING" -> "Pending". */
function capitalize(s: string): string {
  return s.charAt(0) + s.slice(1).toLowerCase();
}

/** "TRIP-001", "INC-014" — a display-only sequence number, never the
 * real database id (see section 6's "no unnecessary technical fields") —
 * assigned by the export itself, so it only means "row N of this file",
 * not a stable identifier across exports. */
function sequentialId(prefix: string, zeroBasedIndex: number): string {
  return `${prefix}-${String(zeroBasedIndex + 1).padStart(3, '0')}`;
}

/** "47 min" / "1h 5min" — null endIso (still-active trip) returns "—". */
function formatDuration(startIso: string, endIso: string | null): string {
  if (!endIso) return '—';
  const ms = new Date(endIso).getTime() - new Date(startIso).getTime();
  const minutes = Math.max(0, Math.round(ms / 60_000));
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return hours > 0 ? `${hours}h ${mins}min` : `${mins} min`;
}

function WalletIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="6" width="18" height="13" rx="2" />
      <path d="M3 10h18" />
      <circle cx="16.5" cy="14" r="1.2" fill="currentColor" stroke="none" />
    </svg>
  );
}

function ExpenseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M4 19V9l8-5 8 5v10" />
      <path d="M9 19v-6h6v6" />
    </svg>
  );
}

function NetIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="M8 12h8M12 8v8" />
    </svg>
  );
}

function TripIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2.4" />
      <path d="M12 3v6.6M4.5 16.5l5-3.2M19.5 16.5l-5-3.2" />
    </svg>
  );
}

function DownloadIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3v13M7 11l5 5 5-5" />
      <path d="M4 19.5h16" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="11" cy="11" r="7" />
      <path d="m21 21-4-4" />
    </svg>
  );
}

function ChartIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M4 20V10M12 20V4M20 20v-7" strokeLinecap="round" />
    </svg>
  );
}

function DriverSmallIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2" />
      <path d="M12 4v5M5 17l4.5-3M19 17l-4.5-3" strokeLinecap="round" />
    </svg>
  );
}

const RANGE_OPTIONS = [
  { label: '7 days', days: 7 },
  { label: '30 days', days: 30 },
  { label: '90 days', days: 90 },
];

type ExportKind = 'drivers' | 'commuters' | 'trips' | 'complaints';

const EXPORT_BUTTONS: { kind: ExportKind; label: string; scopedToRange: boolean }[] = [
  { kind: 'drivers', label: 'Drivers', scopedToRange: false },
  { kind: 'commuters', label: 'Commuters', scopedToRange: false },
  { kind: 'trips', label: 'Trips', scopedToRange: true },
  { kind: 'complaints', label: 'Incident Reports', scopedToRange: true },
];

export default function ReportsPage() {
  const [days, setDays] = useState(30);
  const [report, setReport] = useState<OperationsReport | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [exportingKind, setExportingKind] = useState<ExportKind | null>(null);
  const [isExportingOperations, setIsExportingOperations] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const [driverSearch, setDriverSearch] = useState('');

  // Date filter for the "Also export" buttons only — independent of the
  // chart's 7/30/90-day range above. Leaving both empty keeps each
  // export's own default (full roster for Drivers/Commuters, the
  // 7/30/90-day range for Trips/Incident Reports); filling just one
  // exports that single day. Custom instants are computed the same way
  // Trip History's own Custom Date Range picker does (manilaDateRangeForCustom).
  const [exportFrom, setExportFrom] = useState('');
  const [exportTo, setExportTo] = useState('');

  const exportDateRange = useMemo(() => {
    if (!exportFrom && !exportTo) return null;
    return manilaDateRangeForCustom(exportFrom || exportTo, exportTo || exportFrom);
  }, [exportFrom, exportTo]);

  /** Label used both in each export's CSV header row and its filename. */
  const exportRangeLabel = exportFrom || exportTo
    ? exportFrom && exportTo && exportFrom !== exportTo
      ? `${exportFrom} to ${exportTo}`
      : exportFrom || exportTo
    : null;

  function fetchReport() {
    apiClient
      .get<OperationsReport>(`/api/admin/operations-report?days=${days}`)
      .then((res) => {
        setReport(res);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load the operations report.'));
  }

  useEffect(fetchReport, [days]);
  usePolling(fetchReport, 30_000);

  const filteredPerDriver = useMemo(() => {
    if (!report) return [];
    const q = driverSearch.trim().toLowerCase();
    if (!q) return report.perDriver;
    return report.perDriver.filter(
      (row) => row.driverName.toLowerCase().includes(q) || row.plateNumber.toLowerCase().includes(q),
    );
  }, [report, driverSearch]);

  async function handleExport() {
    if (isExportingOperations) return;
    setExportError(null);
    setIsExportingOperations(true);
    try {
      // Fetched fresh rather than reused from the already-loaded `report`
      // state — this endpoint's summary/daily/perDriver all come from one
      // self-consistent snapshot (summary totals exactly equal the sum of
      // the daily/per-driver rows sitting right below them), which matters
      // more here than millisecond-perfect sync with a screen that's
      // already up to 30s stale from its own last poll anyway.
      const res = await apiClient.get<OperationsReportExport>(`/api/admin/operations-report/export?days=${days}`);
      const today = new Date();
      const generatedLine = `Generated: ${formatLongDate(today)}`;
      const periodLine = `Report Period: ${res.reportPeriodLabel}`;

      // A CSV has no sheets, so the Summary / Daily Breakdown / By Driver
      // views that used to be separate worksheets are three sections of the
      // one file, each under its own title block.
      const rows: CsvRows = [];

      // --- Section 1: Summary --------------------------------------------
      addTitleBlock(rows, 'MANIBELAPP OPERATIONS REPORT', [periodLine, generatedLine]);
      addSectionHeader(rows, 'Summary');
      const metricColumns: ColumnSpec[] = [
        { header: 'Metric', type: 'text' },
        { header: 'Value', type: 'number' },
      ];
      addTable(rows, metricColumns, [
        ['Total Earnings (PHP)', money(res.summary.totalEarnings)],
        ['Total Expenses (PHP)', money(res.summary.totalExpenses)],
        ['Net Income (PHP)', money(res.summary.netIncome)],
        ['Total Trips', res.summary.totalTrips],
        ['Days With Logged Entries', res.summary.daysWithLogs],
      ]);

      addSectionHeader(rows, 'Expense Breakdown');
      addTable(
        rows,
        [
          { header: 'Expense Type', type: 'text' },
          { header: 'Amount (PHP)', type: 'currency' },
        ],
        [
          ['Fuel', res.summary.totalFuelExpense],
          ['Other Expenses', res.summary.totalOtherExpenses],
        ],
        ['Total Expenses', res.summary.totalExpenses],
      );

      // Expense Distribution — same two amounts as a share of total
      // expenses (fractions in, percentages out; see addTable).
      addSectionHeader(rows, 'Expense Distribution');
      addTable(
        rows,
        [
          { header: 'Expense Type', type: 'text' },
          { header: 'Percentage (%)', type: 'percent' },
        ],
        [
          ['Fuel', safeDivide(res.summary.totalFuelExpense, res.summary.totalExpenses)],
          ['Other Expenses', safeDivide(res.summary.totalOtherExpenses, res.summary.totalExpenses)],
        ],
        ['Total Expenses', res.summary.totalExpenses > 0 ? 1 : 0],
      );

      // Performance Summary — calculated operational averages. "Per day"
      // here always means per *logged* day (daysWithLogs), never the raw
      // length of the selected period — a period with unlogged days would
      // otherwise understate what a driver typically earns/spends on a
      // day they actually work, and mixing denominators across these five
      // rows would make them impossible to compare against each other.
      addSectionHeader(rows, 'Performance Summary');
      addTable(rows, metricColumns, [
        ['Average Earnings / Day (PHP)', money(safeDivide(res.summary.totalEarnings, res.summary.daysWithLogs))],
        ['Average Expenses / Day (PHP)', money(safeDivide(res.summary.totalExpenses, res.summary.daysWithLogs))],
        ['Average Net Income / Day (PHP)', money(safeDivide(res.summary.netIncome, res.summary.daysWithLogs))],
        ['Average Earnings / Trip (PHP)', money(safeDivide(res.summary.totalEarnings, res.summary.totalTrips))],
        ['Average Trips / Day', money(safeDivide(res.summary.totalTrips, res.summary.daysWithLogs))],
      ]);

      // --- Section 2: Daily Breakdown ------------------------------------
      addTitleBlock(rows, 'MANIBELAPP OPERATIONS REPORT', [periodLine, generatedLine, 'Daily Breakdown']);
      addTable(
        rows,
        [
          { header: 'Date', type: 'text' },
          { header: 'Earnings (PHP)', type: 'currency' },
          { header: 'Fuel (PHP)', type: 'currency' },
          { header: 'Other Expenses (PHP)', type: 'currency' },
          { header: 'Total Expenses (PHP)', type: 'currency' },
          { header: 'Net Income (PHP)', type: 'currency' },
          { header: 'Trips', type: 'number' },
        ],
        res.daily.map((d) => [d.date, d.earnings, d.fuelExpense, d.otherExpenses, d.totalExpenses, d.netIncome, d.trips]),
        [
          'TOTAL',
          sumBy(res.daily, (d) => d.earnings),
          sumBy(res.daily, (d) => d.fuelExpense),
          sumBy(res.daily, (d) => d.otherExpenses),
          sumBy(res.daily, (d) => d.totalExpenses),
          sumBy(res.daily, (d) => d.netIncome),
          sumBy(res.daily, (d) => d.trips),
        ],
      );

      // --- Section 3: By Driver ------------------------------------------
      addTitleBlock(rows, 'MANIBELAPP OPERATIONS REPORT', [periodLine, generatedLine, 'By Driver']);
      addTable(
        rows,
        [
          { header: 'Driver', type: 'text' },
          { header: 'Plate Number', type: 'text' },
          { header: 'Earnings (PHP)', type: 'currency' },
          { header: 'Fuel (PHP)', type: 'currency' },
          { header: 'Other Expenses (PHP)', type: 'currency' },
          { header: 'Net Income (PHP)', type: 'currency' },
          { header: 'Trips', type: 'number' },
          { header: 'Days Logged', type: 'number' },
        ],
        res.perDriver.map((d) => [
          d.driverName,
          d.plateNumber,
          d.earnings,
          d.fuelExpense,
          d.otherExpenses,
          d.netIncome,
          d.trips,
          d.daysLogged,
        ]),
        [
          'TOTAL',
          '',
          sumBy(res.perDriver, (d) => d.earnings),
          sumBy(res.perDriver, (d) => d.fuelExpense),
          sumBy(res.perDriver, (d) => d.otherExpenses),
          sumBy(res.perDriver, (d) => d.netIncome),
          sumBy(res.perDriver, (d) => d.trips),
          sumBy(res.perDriver, (d) => d.daysLogged),
        ],
      );

      downloadCsv(rows, `operations-report-${days}days-${isoDate(today)}.csv`);
    } catch (err) {
      setExportError(err instanceof ApiError ? err.message : 'Could not export the Operations Report.');
    } finally {
      setIsExportingOperations(false);
    }
  }

  async function handleDatasetExport(kind: ExportKind) {
    if (exportingKind) return;
    setExportError(null);
    setExportingKind(kind);
    const today = new Date();
    const generatedLine = `Generated: ${formatLongDate(today)}`;
    const periodLine = `Report Period: ${exportRangeLabel ?? `Last ${days} Days`}`;

    // Drivers/Commuters have no other date scope, so an explicit filter is
    // the only date query they ever send. Trips/Incident Reports fall back
    // to the 7/30/90-day range above when the admin hasn't set one here.
    const dateParams = exportDateRange ? `dateFrom=${exportDateRange.from}&dateTo=${exportDateRange.to}` : '';
    const rangedParams = dateParams || `days=${days}`;
    const fileSuffix = exportRangeLabel ? exportRangeLabel.replace(' to ', '_to_') : isoDate(today);

    /** The "export capped" notice, if the backend truncated the rows. */
    function addTruncationNote(rows: CsvRows, shownCount: number, noun: string) {
      addNote(rows, `Export capped — showing the ${shownCount} most recent ${noun}.`);
    }

    try {
      switch (kind) {
        case 'drivers': {
          const res = await apiClient.get<{ rows: DriverExportRow[]; summary: DriverExportSummary; truncated: boolean }>(
            `/api/admin/export/drivers${dateParams ? `?${dateParams}` : ''}`,
          );
          const rows: CsvRows = [];
          addTitleBlock(rows, 'MANIBELAPP DRIVER REPORT', [
            ...(exportRangeLabel ? [`Joined: ${exportRangeLabel}`] : []),
            generatedLine,
          ]);
          addSectionHeader(rows, 'Summary');
          addTable(
            rows,
            [
              { header: 'Metric', type: 'text' },
              { header: 'Value', type: 'number' },
            ],
            [
              ['Total Drivers', res.summary.totalDrivers],
              ['Active Drivers', res.summary.activeDrivers],
              ['Inactive Drivers', res.summary.inactiveDrivers],
            ],
          );
          addSectionHeader(rows, 'Drivers');
          addTable(
            rows,
            [
              { header: 'Driver Name', type: 'text' },
              { header: 'Driver ID', type: 'text' },
              { header: 'Phone Number', type: 'text' },
              { header: 'Plate Number', type: 'text' },
              { header: 'Route', type: 'text' },
              { header: 'Verification Status', type: 'text' },
              { header: 'Account Status', type: 'text' },
              { header: 'Date Registered', type: 'text' },
              { header: 'Total Trips', type: 'number' },
              { header: 'Completed Trips', type: 'number' },
            ],
            res.rows.map((r) => [
              r.fullName,
              r.driverId,
              formatPhoneForCsv(r.mobileNumber),
              r.plateNumber,
              r.route,
              r.licenseVerified ? 'Verified' : 'Pending',
              r.isActive ? 'Active' : 'Inactive',
              formatManilaDate(r.createdAt),
              r.totalTrips,
              r.completedTrips,
            ]),
            ['TOTAL', '', '', '', '', '', '', '', sumBy(res.rows, (r) => r.totalTrips), sumBy(res.rows, (r) => r.completedTrips)],
          );
          if (res.truncated) addTruncationNote(rows, res.rows.length, 'recently joined drivers');
          downloadCsv(rows, `drivers-${fileSuffix}.csv`);
          break;
        }
        case 'commuters': {
          const res = await apiClient.get<{ rows: CommuterExportRow[]; summary: CommuterExportSummary; truncated: boolean }>(
            `/api/admin/export/commuters${dateParams ? `?${dateParams}` : ''}`,
          );
          const rows: CsvRows = [];
          addTitleBlock(rows, 'MANIBELAPP COMMUTER REPORT', [
            ...(exportRangeLabel ? [`Joined: ${exportRangeLabel}`] : []),
            generatedLine,
          ]);
          addSectionHeader(rows, 'Summary');
          addTable(
            rows,
            [
              { header: 'Metric', type: 'text' },
              { header: 'Value', type: 'number' },
            ],
            [
              ['Total Commuters', res.summary.totalCommuters],
              ['Active Commuters', res.summary.activeCommuters],
              ['Inactive Commuters', res.summary.inactiveCommuters],
              ['Phone Verified', res.summary.phoneVerified],
              ['Pending ID Verification', res.summary.pendingVerification],
              ['Approved ID Verification', res.summary.approvedVerification],
              ['Rejected ID Verification', res.summary.rejectedVerification],
            ],
          );
          addSectionHeader(rows, 'Commuters');
          addTable(
            rows,
            [
              { header: 'Commuter Name', type: 'text' },
              { header: 'Commuter ID', type: 'text' },
              { header: 'Phone Number', type: 'text' },
              { header: 'Verification Status', type: 'text' },
              { header: 'ID Verification Status', type: 'text' },
              { header: 'Account Status', type: 'text' },
              { header: 'Date Registered', type: 'text' },
              { header: 'Total Trips', type: 'number' },
            ],
            res.rows.map((r) => [
              r.fullName,
              r.commuterId,
              formatPhoneForCsv(r.mobileNumber),
              r.phoneVerified ? 'Verified' : 'Not Verified',
              r.verificationStatus ? capitalize(r.verificationStatus) : 'Not Submitted',
              r.isActive ? 'Active' : 'Inactive',
              formatManilaDate(r.createdAt),
              r.totalTrips,
            ]),
            ['TOTAL', '', '', '', '', '', '', sumBy(res.rows, (r) => r.totalTrips)],
          );
          if (res.truncated) addTruncationNote(rows, res.rows.length, 'recently joined commuters');
          downloadCsv(rows, `commuters-${fileSuffix}.csv`);
          break;
        }
        case 'trips': {
          const res = await apiClient.get<{ rows: TripExportRow[]; summary: TripExportSummary; truncated: boolean }>(
            `/api/admin/export/trips?${rangedParams}`,
          );
          const rows: CsvRows = [];
          addTitleBlock(rows, 'MANIBELAPP TRIP REPORT', [periodLine, generatedLine]);
          addSectionHeader(rows, 'Summary');
          addTable(
            rows,
            [
              { header: 'Metric', type: 'text' },
              { header: 'Value', type: 'number' },
            ],
            [
              ['Total Trips', res.summary.totalTrips],
              ['Completed', res.summary.completedTrips],
              ['Active', res.summary.activeTrips],
              ['Short Trips Flagged', res.summary.shortTripsFlagged],
            ],
          );
          addSectionHeader(rows, 'Trips');
          // Chronological ascending (oldest first) so Trip Number climbs
          // top to bottom the way a reader expects — the backend returns
          // newest-first, matching its other list endpoints' convention.
          const orderedTrips = [...res.rows].sort(
            (a, b) => new Date(a.startedAt).getTime() - new Date(b.startedAt).getTime(),
          );
          addTable(
            rows,
            [
              { header: 'Trip Number', type: 'text' },
              { header: 'Driver', type: 'text' },
              { header: 'Plate Number', type: 'text' },
              { header: 'Route', type: 'text' },
              { header: 'Trip Date', type: 'text' },
              { header: 'Start Time', type: 'text' },
              { header: 'End Time', type: 'text' },
              { header: 'Duration', type: 'text' },
              { header: 'Trip Status', type: 'text' },
              { header: 'Flag', type: 'text' },
            ],
            orderedTrips.map((r, i) => [
              sequentialId('TRIP', i),
              r.driverName,
              r.plateNumber,
              r.route,
              formatManilaDate(r.startedAt),
              formatManilaTime(r.startedAt),
              r.endedAt ? formatManilaTime(r.endedAt) : null,
              formatDuration(r.startedAt, r.endedAt),
              r.status === 'COMPLETED' ? 'Completed' : 'Active',
              r.isShortTrip ? 'Short Trip – Flagged' : '—',
            ]),
          );
          if (res.truncated) addTruncationNote(rows, res.rows.length, 'trips in this range');
          downloadCsv(rows, `trips-${fileSuffix}.csv`);
          break;
        }
        case 'complaints': {
          const res = await apiClient.get<{ rows: ComplaintExportRow[]; summary: ComplaintExportSummary; truncated: boolean }>(
            `/api/admin/export/complaints?${rangedParams}`,
          );
          const rows: CsvRows = [];
          addTitleBlock(rows, 'MANIBELAPP INCIDENT REPORT', [periodLine, generatedLine]);
          addSectionHeader(rows, 'Summary');
          addTable(
            rows,
            [
              { header: 'Metric', type: 'text' },
              { header: 'Value', type: 'number' },
            ],
            [
              ['Total Complaints', res.summary.totalComplaints],
              ['Pending', res.summary.pending],
              ['Investigating', res.summary.investigating],
              ['Resolved', res.summary.resolved],
              ['Rejected', res.summary.rejected],
            ],
          );
          addSectionHeader(rows, 'Incident Reports');
          const orderedComplaints = [...res.rows].sort(
            (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
          );
          addTable(
            rows,
            [
              { header: 'Incident ID', type: 'text' },
              { header: 'Date', type: 'text' },
              { header: 'Time', type: 'text' },
              { header: 'Type', type: 'text' },
              { header: 'Driver', type: 'text' },
              { header: 'Plate Number', type: 'text' },
              { header: 'Route', type: 'text' },
              { header: 'Description', type: 'text' },
              { header: 'Status', type: 'text' },
              { header: 'Resolution', type: 'text' },
              { header: 'Date Resolved', type: 'text' },
            ],
            orderedComplaints.map((r, i) => [
              sequentialId('INC', i),
              formatManilaDate(r.createdAt),
              formatManilaTime(r.createdAt),
              r.complaintType,
              r.driverName,
              r.plateNumber,
              r.route,
              r.description,
              capitalize(r.status),
              r.resolution ? capitalize(r.resolution) : '—',
              r.resolvedAt ? formatManilaDate(r.resolvedAt) : null,
            ]),
          );
          if (res.truncated) addTruncationNote(rows, res.rows.length, 'reports in this range');
          downloadCsv(rows, `incident-reports-${fileSuffix}.csv`);
          break;
        }
      }
    } catch (err) {
      setExportError(err instanceof ApiError ? err.message : `Could not export ${kind}.`);
    } finally {
      setExportingKind(null);
    }
  }

  return (
    <DashboardLayout title="Reports">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p className="text-sm text-gray-500">
            Operations report — earnings, fuel, and other expenses drivers log each day.
          </p>
        </div>

        <div className="flex items-center gap-3">
          {/* Date-range filter — one row, above the chart. */}
          <div className="flex items-center gap-1 rounded-lg border border-border-subtle bg-surface-card p-1">
            {RANGE_OPTIONS.map((opt) => (
              <button
                key={opt.days}
                onClick={() => setDays(opt.days)}
                className={`rounded-md px-3 py-1.5 text-sm font-medium transition ${
                  days === opt.days ? 'bg-brand-blue text-white' : 'text-gray-600 hover:bg-gray-100'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>

          <button
            onClick={handleExport}
            disabled={!report || isExportingOperations}
            className="flex items-center gap-2 rounded-lg border border-border-subtle bg-surface-card px-3.5 py-2 text-sm font-medium text-gray-700 transition hover:border-brand-blue hover:text-brand-blue disabled:cursor-not-allowed disabled:opacity-50"
          >
            <DownloadIcon />
            {isExportingOperations ? 'Exporting...' : 'Export Operations Report'}
          </button>
        </div>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-gray-400">Also export:</span>
        {EXPORT_BUTTONS.map((btn) => (
          <button
            key={btn.kind}
            onClick={() => handleDatasetExport(btn.kind)}
            disabled={exportingKind !== null}
            title={
              exportRangeLabel
                ? `Scoped to ${exportRangeLabel}`
                : btn.scopedToRange
                  ? `Scoped to the selected ${days}-day range`
                  : 'Full roster'
            }
            className="flex items-center gap-1.5 rounded-lg border border-border-subtle bg-surface-card px-3 py-1.5 text-xs font-medium text-gray-600 transition hover:border-brand-blue hover:text-brand-blue disabled:cursor-not-allowed disabled:opacity-50"
          >
            <DownloadIcon />
            {exportingKind === btn.kind ? 'Exporting...' : btn.label}
          </button>
        ))}

        <div className="ml-1 flex items-center gap-1.5">
          <span className="text-xs text-gray-400">on/between</span>
          <input
            type="date"
            value={exportFrom}
            onChange={(e) => setExportFrom(e.target.value)}
            max={exportTo || undefined}
            className="rounded-lg border border-border-subtle px-2 py-1.5 text-xs text-gray-600 focus:border-brand-blue focus:outline-none"
          />
          <span className="text-xs text-gray-400">to</span>
          <input
            type="date"
            value={exportTo}
            onChange={(e) => setExportTo(e.target.value)}
            min={exportFrom || undefined}
            className="rounded-lg border border-border-subtle px-2 py-1.5 text-xs text-gray-600 focus:border-brand-blue focus:outline-none"
          />
          {(exportFrom || exportTo) && (
            <button
              onClick={() => {
                setExportFrom('');
                setExportTo('');
              }}
              className="text-xs font-semibold text-gray-400 hover:text-brand-blue"
            >
              Clear
            </button>
          )}
        </div>
      </div>
      {exportRangeLabel && (
        <p className="mt-1.5 text-xs text-gray-400">
          "Also export" buttons above will be scoped to <span className="font-medium text-gray-600">{exportRangeLabel}</span>.
        </p>
      )}

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {exportError && <p className="mt-2 text-sm font-medium text-brand-red">{exportError}</p>}

      {!report && !error && (
        <div className="animate-pulse">
          <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <StatCardSkeleton key={i} />
            ))}
          </div>
          <div className="mt-6 rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
            <div className="h-4 w-48 rounded bg-gray-100" />
            <div className="mt-4 h-[260px] w-full rounded-lg bg-gray-100" />
          </div>
          <TableSkeleton columns={7} />
        </div>
      )}

      {report && (
        <>
          <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard label="Total Earnings" value={formatPeso(report.totalEarnings)} icon={<WalletIcon />} />
            <StatCard
              label="Total Expenses"
              value={formatPeso(report.totalFuelExpense + report.totalOtherExpenses)}
              icon={<ExpenseIcon />}
            />
            <StatCard label="Net Income" value={formatPeso(report.netIncome)} icon={<NetIcon />} />
            <StatCard label="Total Trips" value={report.totalTrips} icon={<TripIcon />} />
          </div>

          <Card className="mt-6">
            <SectionHeader icon={<ChartIcon />} title="Earnings vs. Expenses" />
            <p className="pl-9 text-xs text-gray-500">
              {report.daysWithLogs} day{report.daysWithLogs === 1 ? '' : 's'} with logged entries in the last {days} days.
            </p>
            <div className="mt-4">
              <MoneyTrendChart series={report.series} />
            </div>
          </Card>

          <div className="mt-6 rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
            <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border-subtle px-5 py-4">
              <SectionHeader icon={<DriverSmallIcon />} title="By Driver" />
              <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-white px-3 py-1.5 sm:w-64">
                <SearchIcon />
                <input
                  value={driverSearch}
                  onChange={(e) => setDriverSearch(e.target.value)}
                  placeholder="Search driver or plate"
                  className="w-full text-sm text-gray-700 focus:outline-none"
                />
              </div>
            </div>
            {report.perDriver.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-gray-400">No driver has logged operations in this range yet.</p>
            ) : filteredPerDriver.length === 0 ? (
              <p className="px-5 py-8 text-center text-sm text-gray-400">No driver matches "{driverSearch}".</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[720px] text-left text-sm">
                  <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                    <tr>
                      <th className="px-5 py-3">Driver</th>
                      <th className="px-5 py-3">Plate Number</th>
                      <th className="px-5 py-3 text-right">Earnings</th>
                      <th className="px-5 py-3 text-right">Fuel</th>
                      <th className="px-5 py-3 text-right">Other</th>
                      <th className="px-5 py-3 text-right">Net</th>
                      <th className="px-5 py-3 text-right">Days Logged</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {filteredPerDriver.map((row) => (
                      <tr key={row.driverId} className="hover:bg-gray-50">
                        <td className="px-5 py-3 font-medium text-gray-900">{row.driverName}</td>
                        <td className="px-5 py-3 text-gray-600">{row.plateNumber}</td>
                        <td className="tabular-nums px-5 py-3 text-right text-gray-900">{formatPeso(row.earnings)}</td>
                        <td className="tabular-nums px-5 py-3 text-right text-gray-600">{formatPeso(row.fuelExpense)}</td>
                        <td className="tabular-nums px-5 py-3 text-right text-gray-600">{formatPeso(row.otherExpenses)}</td>
                        <td className="tabular-nums px-5 py-3 text-right font-semibold text-gray-900">{formatPeso(row.netIncome)}</td>
                        <td className="tabular-nums px-5 py-3 text-right text-gray-600">{row.daysLogged}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </>
      )}
    </DashboardLayout>
  );
}
