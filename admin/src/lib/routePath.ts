// The real, officially-registered Pasig-Quiapo PUJ route (DOTr/Sakay route
// DOTR:R_SAKAY_2018_PUJ_657 — https://explore.sakay.ph/routes/DOTR:R_SAKAY_2018_PUJ_657):
// Caruncho Ave./Market Ave., Pasig <-> Arlegui / Quezon Blvd., Manila via
// Shaw Blvd., Victorio Mapa Blvd. and Ramon Magsaysay Blvd. The Pasig ->
// Quiapo path is the shape Sakay publishes for the route's outbound trip
// (T_SAKAY_2018_1316), simplified with Douglas-Peucker at ~3 m so the
// polyline stays light, and is the single source of truth for the corridor:
// Quiapo -> Pasig is that same path in reverse (see QUIAPO_PASIG_ROUTE), not
// a separately stored shape.

// Pasig -> Quiapo (trip T_SAKAY_2018_1316).
const PASIG_QUIAPO_ROUTE: [number, number][] = [
  [14.559610, 121.083800],
  [14.560670, 121.080950],
  [14.559830, 121.080650],
  [14.560970, 121.077560],
  [14.560790, 121.077480],
  [14.560750, 121.077360],
  [14.560860, 121.076640],
  [14.561920, 121.076730],
  [14.563940, 121.076550],
  [14.563850, 121.077350],
  [14.563890, 121.077440],
  [14.564670, 121.077480],
  [14.564870, 121.077390],
  [14.564510, 121.076550],
  [14.564710, 121.076450],
  [14.565250, 121.075990],
  [14.565260, 121.076100],
  [14.565520, 121.076640],
  [14.565940, 121.077300],
  [14.565760, 121.077390],
  [14.565940, 121.077300],
  [14.566120, 121.077660],
  [14.566240, 121.077120],
  [14.566090, 121.076140],
  [14.566350, 121.072070],
  [14.566380, 121.071280],
  [14.566340, 121.071010],
  [14.566110, 121.070470],
  [14.566110, 121.070270],
  [14.565320, 121.070050],
  [14.564480, 121.069680],
  [14.564640, 121.069480],
  [14.564460, 121.069430],
  [14.564280, 121.069570],
  [14.563480, 121.069060],
  [14.563170, 121.068700],
  [14.562960, 121.068120],
  [14.562880, 121.067430],
  [14.562940, 121.066720],
  [14.563250, 121.065680],
  [14.563350, 121.065540],
  [14.563500, 121.065470],
  [14.563840, 121.065470],
  [14.564960, 121.065680],
  [14.566000, 121.065810],
  [14.566090, 121.066180],
  [14.566230, 121.066200],
  [14.566160, 121.065840],
  [14.567880, 121.066140],
  [14.567880, 121.066280],
  [14.567920, 121.066310],
  [14.567990, 121.066290],
  [14.568030, 121.066170],
  [14.570030, 121.066550],
  [14.570220, 121.066530],
  [14.570360, 121.066460],
  [14.573300, 121.062970],
  [14.574360, 121.061780],
  [14.574530, 121.061710],
  [14.574800, 121.061360],
  [14.574830, 121.061230],
  [14.577900, 121.057610],
  [14.579400, 121.055960],
  [14.581780, 121.053220],
  [14.583050, 121.051690],
  [14.583560, 121.050970],
  [14.584560, 121.049790],
  [14.586250, 121.047650],
  [14.587290, 121.046430],
  [14.588030, 121.044920],
  [14.588960, 121.042400],
  [14.589480, 121.040430],
  [14.589550, 121.039840],
  [14.589410, 121.035390],
  [14.589540, 121.035180],
  [14.590000, 121.034660],
  [14.590360, 121.034070],
  [14.592260, 121.029840],
  [14.592930, 121.028720],
  [14.593230, 121.028120],
  [14.593640, 121.027120],
  [14.593730, 121.027000],
  [14.594180, 121.025720],
  [14.594170, 121.025600],
  [14.596160, 121.020460],
  [14.595930, 121.019980],
  [14.595970, 121.019830],
  [14.597590, 121.017630],
  [14.599690, 121.016950],
  [14.600840, 121.016640],
  [14.603020, 121.015890],
  [14.602850, 121.015580],
  [14.602680, 121.014960],
  [14.602270, 121.010270],
  [14.602310, 121.010070],
  [14.602240, 121.009880],
  [14.602160, 121.008590],
  [14.601910, 121.006560],
  [14.601350, 121.000500],
  [14.601270, 121.000150],
  [14.600910, 120.999390],
  [14.601140, 120.998850],
  [14.601160, 120.998470],
  [14.600960, 120.997350],
  [14.600580, 120.996270],
  [14.600640, 120.995850],
  [14.601520, 120.993130],
  [14.601580, 120.992850],
  [14.601560, 120.992650],
  [14.600990, 120.991610],
  [14.600280, 120.990810],
  [14.597750, 120.989560],
  [14.597490, 120.989510],
  [14.596760, 120.989540],
  [14.596530, 120.989480],
  [14.597200, 120.985010],
];

// Quiapo -> Pasig. Not a second hand-maintained shape: it is the Pasig ->
// Quiapo path above, walked in the opposite direction, so the two
// directions can never drift apart (same road, Ramon Magsaysay Blvd. and
// Victorio Mapa Blvd. included). Kept identical to RoutePath.quiapoToPasig
// in the Flutter app's lib/core/constants/route_path.dart.
const QUIAPO_PASIG_ROUTE: [number, number][] = [...PASIG_QUIAPO_ROUTE].reverse();

export interface RouteDefinition {
  id: string;
  /** Shown on the legend/toggle button. */
  legendLabel: string;
  /** The exact directional string this is recorded as everywhere else
   * (see DRIVER_ROUTES in backend/src/routes/admin.ts). Each direction is
   * its own independently-toggleable entry rather than one entry bundling
   * both — two same-corridor lines shown together (even color-coded) read
   * as confusing clutter; a toggle per direction, each labeled with the
   * exact direction it is, doesn't need any of that disambiguation. */
  direction: string;
  path: [number, number][];
  color: string;
  caseColor: string;
}

// A third direction/corridor later is just adding another entry here
// (plus the matching RoutePath.forRoute case on the Flutter side, and the
// new direction string in every kDriverRoutes-equivalent list) — nothing
// about how LiveMap draws or filters routes needs to change. Only add one
// once it's independently confirmed as an actual registered route, the
// same way these two were checked against the public GTFS feed.
export const ROUTES: RouteDefinition[] = [
  {
    id: 'pasig-quiapo',
    legendLabel: 'Pasig – Quiapo',
    direction: 'Pasig – Quiapo',
    path: PASIG_QUIAPO_ROUTE,
    color: '#EAB308',
    caseColor: '#92600A',
  },
  {
    id: 'quiapo-pasig',
    legendLabel: 'Quiapo – Pasig',
    direction: 'Quiapo – Pasig',
    // PASIG_QUIAPO_ROUTE reversed — see QUIAPO_PASIG_ROUTE above.
    path: QUIAPO_PASIG_ROUTE,
    color: '#0B57D0',
    caseColor: '#083D94',
  },
];

/** Whether `route` belongs to any of the given route ids — the filtering
 * rule behind "only show markers on the directions currently toggled
 * on". */
export function matchesAnyRoute(route: string | null | undefined, routeIds: Set<string>): boolean {
  if (!route) return false;
  return ROUTES.some((r) => routeIds.has(r.id) && r.direction === route);
}
