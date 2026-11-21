import { prisma } from './prisma';

/**
 * Business rules MANIBELA has not signed off on yet. Each one has a default
 * here and can be overridden from the admin site (stored in SystemSetting),
 * so changing a threshold never needs a deploy. `confirm` marks the ones that
 * still need the client's confirmation — the admin UI flags them.
 */
export interface SettingDef {
  default: number | boolean | null;
  type: 'number' | 'boolean';
  min?: number;
  max?: number;
  label: string;
  help: string;
  /** Proposed, not an approved MANIBELA policy. */
  confirm: boolean;
  /** number settings only: null is a legal value ("not configured"). */
  nullable?: boolean;
}

export const SETTING_DEFS = {
  nearFullThresholdPercent: {
    default: 80,
    type: 'number',
    min: 1,
    max: 100,
    label: 'Nearly-full threshold (%)',
    help: 'Occupancy at or above this % of seating capacity shows NEARLY FULL.',
    confirm: true,
  },
  boardingProximityMeters: {
    default: 20,
    type: 'number',
    min: 5,
    max: 200,
    label: 'Boarding distance (m)',
    help: 'How close the commuter must be to the jeepney for boarding to be confirmed.',
    confirm: false,
  },
  boardingAccuracyAllowanceMeters: {
    default: 15,
    type: 'number',
    min: 0,
    max: 100,
    label: 'GPS accuracy allowance (m)',
    help: 'At most this much of the commuter phone\'s reported GPS error is added to the boarding distance.',
    confirm: false,
  },
  boardingMaxAccuracyMeters: {
    default: 50,
    type: 'number',
    min: 5,
    max: 500,
    label: 'Worst usable GPS accuracy (m)',
    help: 'Commuter readings less accurate than this are ignored.',
    confirm: false,
  },
  boardingRequiredReadings: {
    default: 3,
    type: 'number',
    min: 1,
    max: 10,
    label: 'Consecutive good readings needed',
    help: 'How many back-to-back in-range GPS readings confirm a boarding.',
    confirm: false,
  },
  boardingMinWindowSeconds: {
    default: 4,
    type: 'number',
    min: 0,
    max: 60,
    label: 'Minimum verification window (s)',
    help: 'The good readings must span at least this long.',
    confirm: false,
  },
  boardingRequestTtlSeconds: {
    default: 60,
    type: 'number',
    min: 10,
    max: 600,
    label: 'Verification time limit (s)',
    help: 'A boarding request that is not confirmed within this time fails.',
    confirm: false,
  },
  boardingMaxFixAgeSeconds: {
    default: 15,
    type: 'number',
    min: 1,
    max: 300,
    label: 'Oldest usable commuter GPS fix (s)',
    help: 'A commuter GPS fix older than this is treated as stale.',
    confirm: false,
  },
  boardingDriverMaxAgeSeconds: {
    default: 60,
    type: 'number',
    min: 5,
    max: 900,
    label: 'Oldest usable driver GPS fix (s)',
    help: 'If the jeepney has not reported its position this recently, boarding cannot be confirmed.',
    confirm: false,
  },
  presenceReleaseDistanceMeters: {
    default: 200,
    type: 'number',
    min: 50,
    max: 2000,
    label: 'Not-on-board distance (m)',
    help: 'After boarding, a passenger whose phone stays farther than this from the jeepney is automatically removed from the count.',
    confirm: false,
  },
  presenceVerifyMoveMeters: {
    default: 100,
    type: 'number',
    min: 30,
    max: 1000,
    label: 'Travel-together distance (m)',
    help: 'Once the jeepney has moved this far since boarding, the commuter must have moved with it. Moving along = verified rider; staying put = not on board.',
    confirm: false,
  },
  presenceUnverifiedTimeoutSeconds: {
    default: 180,
    type: 'number',
    min: 60,
    max: 1800,
    label: 'Unverified-boarding timeout (s)',
    help: 'A boarding that was never seen travelling with the jeepney (phone off, app killed, no signal) is removed after this long, once the jeepney has travelled well away.',
    confirm: true,
  },
  presenceUnverifiedMinTravelMeters: {
    default: 500,
    type: 'number',
    min: 100,
    max: 5000,
    label: 'Jeepney travel before timeout applies (m)',
    help: 'The unverified-boarding timeout only applies once the jeepney has moved at least this far since boarding, so a long stop never removes anyone.',
    confirm: true,
  },
  presenceReleaseReadings: {
    default: 4,
    type: 'number',
    min: 2,
    max: 20,
    label: 'Far-away readings before removal',
    help: 'How many back-to-back usable readings far from the jeepney remove a passenger who did not actually ride.',
    confirm: false,
  },
  presenceReleaseMinSeconds: {
    default: 20,
    type: 'number',
    min: 5,
    max: 300,
    label: 'Far-away time before removal (s)',
    help: 'The far-away readings must also span at least this long.',
    confirm: false,
  },
  shortTripRestrictionThreshold: {
    default: 3,
    type: 'number',
    min: 1,
    max: 50,
    label: 'Short-tripping occurrences before restriction',
    help: 'Qualifying occurrences that trigger a trip-start restriction. Proposed: 3.',
    confirm: true,
  },
  shortTripCountOnlyConfirmed: {
    default: true,
    type: 'boolean',
    label: 'Count only confirmed incidents',
    help: 'On: only reviewed and confirmed incidents count. Off: any non-dismissed report counts.',
    confirm: true,
  },
  shortTripRestrictionMinutes: {
    default: 60,
    type: 'number',
    min: 1,
    max: 10080,
    label: 'Restriction length (minutes)',
    help: 'Proposed: 60 (1 hour) or 120 (2 hours).',
    confirm: true,
  },
  estimatedFarePerPassenger: {
    default: null,
    type: 'number',
    min: 0,
    max: 10000,
    nullable: true,
    label: 'Fare used for earnings ESTIMATES (PHP)',
    help: 'Leave empty to disable estimates. Estimates are never treated as actual income.',
    confirm: true,
  },
} as const satisfies Record<string, SettingDef>;

export type SettingKey = keyof typeof SETTING_DEFS;
export type Settings = { [K in SettingKey]: (typeof SETTING_DEFS)[K]['default'] extends boolean ? boolean : number | null };

const CACHE_MS = 10_000;
let cache: { at: number; values: Record<string, unknown> } | null = null;

export function invalidateSettingsCache() {
  cache = null;
}

export function validateSettingValue(key: SettingKey, value: unknown): number | boolean | null {
  const def: SettingDef = SETTING_DEFS[key];
  if (value === null) {
    if (def.nullable) return null;
    throw new Error(`${def.label} cannot be empty.`);
  }
  if (def.type === 'boolean') {
    if (typeof value !== 'boolean') throw new Error(`${def.label} must be on or off.`);
    return value;
  }
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error(`${def.label} must be a number.`);
  if (def.min !== undefined && value < def.min) throw new Error(`${def.label} must be at least ${def.min}.`);
  if (def.max !== undefined && value > def.max) throw new Error(`${def.label} must be at most ${def.max}.`);
  return value;
}

export async function getSettings(): Promise<Settings> {
  if (!cache || Date.now() - cache.at > CACHE_MS) {
    const rows = await prisma.systemSetting.findMany();
    cache = { at: Date.now(), values: Object.fromEntries(rows.map((r) => [r.key, r.value])) };
  }
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(SETTING_DEFS) as SettingKey[]) {
    const stored = cache.values[key];
    try {
      out[key] = stored === undefined ? SETTING_DEFS[key].default : validateSettingValue(key, stored);
    } catch {
      out[key] = SETTING_DEFS[key].default;
    }
  }
  return out as Settings;
}
