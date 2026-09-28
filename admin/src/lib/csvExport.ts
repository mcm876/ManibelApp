/** Shared building blocks for every report's exported CSV — title block,
 * section headers, header + data (+ optional TOTAL) rows, RFC 4180 quoting,
 * and a browser download. Every report (Operations, Drivers, Commuters,
 * Trips, Incident Reports) is built from these same pieces so they stay one
 * consistent document family.
 *
 * A CSV has no sheets, so a report that used to span several worksheets
 * (the Operations Report) is written as several titled sections one after
 * another in the same file, separated by a blank line.
 */

/** Real numbers stay numbers (so a spreadsheet can still sum/sort them);
 * everything else is text. null becomes an em dash in text columns and an
 * empty cell everywhere else — see [addTable]. */
export type CsvCell = string | number | boolean | null;

export type CsvRows = CsvCell[][];

const MANILA_TZ = 'Asia/Manila';

const manilaPartsFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: MANILA_TZ,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

function manilaParts(iso: string): Record<string, string> {
  const parts: Record<string, string> = {};
  for (const p of manilaPartsFormatter.formatToParts(new Date(iso))) parts[p.type] = p.value;
  return parts;
}

/** "2026-08-14" for an ISO instant, as seen in Asia/Manila — ISO order so
 * it sorts correctly and every spreadsheet locale reads it the same way,
 * regardless of the timezone of the browser generating the file. */
export function formatManilaDate(iso: string): string {
  const p = manilaParts(iso);
  return `${p.year}-${p.month}-${p.day}`;
}

/** "2:05 PM" for an ISO instant, as seen in Asia/Manila. */
export function formatManilaTime(iso: string): string {
  const p = manilaParts(iso);
  const hour24 = Number(p.hour) % 24;
  const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
  return `${hour12}:${p.minute} ${hour24 < 12 ? 'AM' : 'PM'}`;
}

/** Numbers as a plain, locale-independent decimal ("44177.50") — no ₱ sign
 * and no thousands separators, so the cell stays a real number in a
 * spreadsheet instead of turning into text. The currency lives in the
 * column header ("Earnings (PHP)") instead. */
export function money(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Cells that begin with one of these are treated as a formula by
 * Excel/Sheets ("CSV injection") — and the text in a report (names,
 * incident descriptions) comes straight from user input. */
const FORMULA_TRIGGER = /^[=+\-@\t\r]/;
/** A leading +/- followed only by digits and number/phone punctuation
 * ("+63 917 123 4567", "-1,200") can't run anything, so it's left alone
 * rather than being mangled with a visible apostrophe. */
const HARMLESS_SIGNED = /^[+-][\d\s().,-]*$/;

function neutralizeFormula(text: string): string {
  return FORMULA_TRIGGER.test(text) && !HARMLESS_SIGNED.test(text) ? `'${text}` : text;
}

/** RFC 4180 field: wraps in double quotes and doubles any embedded quote
 * whenever the value contains a comma, quote, or line break. */
export function escapeCsvField(cell: CsvCell): string {
  if (cell === null) return '';
  if (typeof cell === 'number') return Number.isFinite(cell) ? String(cell) : '';
  if (typeof cell === 'boolean') return cell ? 'TRUE' : 'FALSE';
  const text = neutralizeFormula(cell);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function buildCsv(rows: CsvRows): string {
  // CRLF is the RFC 4180 line ending and what Excel expects.
  return rows.map((row) => row.map(escapeCsvField).join(',')).join('\r\n') + '\r\n';
}

export type ColumnType = 'text' | 'number' | 'currency' | 'percent';

export interface ColumnSpec {
  header: string;
  type: ColumnType;
}

/** Big title line + one line per entry in `subtitleLines` (report period,
 * "Generated <date>", etc.), then a blank spacer row. */
export function addTitleBlock(rows: CsvRows, title: string, subtitleLines: string[]): void {
  rows.push([title]);
  for (const line of subtitleLines) rows.push([line]);
  rows.push([]);
}

/** A labeled line (e.g. "SUMMARY", "DAILY BREAKDOWN") marking the start of
 * the section beneath it. */
export function addSectionHeader(rows: CsvRows, label: string): void {
  rows.push([label.toUpperCase()]);
}

/** Header row + one row per entry in `data` + an optional TOTAL row, then a
 * blank spacer row. A null in a numeric column reads as 0 ("no fuel expense
 * that day"); in a text column it reads as an em dash ("no flag", "no
 * route yet"). Percent columns take a fraction (0.798) and are written as a
 * percentage number (79.8) — put the "%" in the header. */
export function addTable(rows: CsvRows, columns: ColumnSpec[], data: CsvCell[][], totalRow?: CsvCell[]): void {
  rows.push(columns.map((c) => c.header));
  for (const rowValues of data) {
    rows.push(
      columns.map((col, i) => {
        const raw = rowValues[i] ?? null;
        if (col.type === 'text') return raw ?? '—';
        if (raw === null) return 0;
        if (col.type === 'percent' && typeof raw === 'number') return Math.round(raw * 1000) / 10;
        if (col.type === 'currency' && typeof raw === 'number') return money(raw);
        return raw;
      }),
    );
  }
  if (totalRow) {
    rows.push(
      columns.map((col, i) => {
        const raw = totalRow[i] ?? '';
        if (col.type === 'percent' && typeof raw === 'number') return Math.round(raw * 1000) / 10;
        if (col.type === 'currency' && typeof raw === 'number') return money(raw);
        return raw;
      }),
    );
  }
  rows.push([]);
}

/** A single italic-style note line, e.g. the "export capped" notice. */
export function addNote(rows: CsvRows, text: string): void {
  rows.push([text]);
}

/** Renders `rows` to a .csv file and triggers a browser download. The
 * leading UTF-8 byte-order mark makes Excel read the file as UTF-8, so
 * names with ñ/Ñ, en dashes, and the like don't turn into mojibake. */
export function downloadCsv(rows: CsvRows, filename: string): void {
  const blob = new Blob(['﻿', buildCsv(rows)], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
