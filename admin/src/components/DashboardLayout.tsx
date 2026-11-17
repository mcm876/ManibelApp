import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { NavLink, useLocation, useNavigate } from 'react-router-dom';
import { LogoMark } from './Logo';
import { LogoutConfirmDialog } from './LogoutConfirmDialog';
import { NotificationBell } from './NotificationBell';
import { useAuth, type AdminRole } from '../lib/auth';
import { adminNotificationPath, useAdminNotificationFeed, type AdminNotification } from '../lib/useAdminNotificationFeed';

function GridIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="3" width="8" height="8" rx="1.5" />
      <rect x="13" y="3" width="8" height="8" rx="1.5" />
      <rect x="3" y="13" width="8" height="8" rx="1.5" />
      <rect x="13" y="13" width="8" height="8" rx="1.5" />
    </svg>
  );
}

function SteeringWheelIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2.4" />
      <path d="M12 3v6.6M4.5 16.5l5-3.2M19.5 16.5l-5-3.2" />
    </svg>
  );
}

function PeopleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="9" cy="8" r="3.2" />
      <path d="M2.5 20c0-3.6 2.9-6.2 6.5-6.2s6.5 2.6 6.5 6.2" />
      <circle cx="17.5" cy="9" r="2.6" />
      <path d="M15.8 13.9c2.9.4 4.7 2.6 4.7 6.1" />
    </svg>
  );
}

function BadgeCheckIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 2.5l2.2 1.3 2.5-.3 1 2.3 2.3 1-.3 2.5 1.3 2.2-1.3 2.2.3 2.5-2.3 1-1 2.3-2.5-.3L12 21.5l-2.2-1.3-2.5.3-1-2.3-2.3-1 .3-2.5L3 12l1.3-2.2-.3-2.5 2.3-1 1-2.3 2.5.3z" />
      <path d="m8.5 12.5 2.3 2.3 4.7-4.8" />
    </svg>
  );
}

function RouteIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="5" cy="6" r="2.2" />
      <circle cx="19" cy="18" r="2.2" />
      <path d="M5 8.2V13a4 4 0 0 0 4 4h6" strokeDasharray="1 3.2" />
    </svg>
  );
}

function ReportIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="4" y="3.5" width="16" height="17" rx="2" />
      <path d="M8 13v4M12 9.5v7.5M16 11.5v5.5" />
    </svg>
  );
}

function GearIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 13.5a7.6 7.6 0 0 0 0-3l2-1.5-2-3.4-2.4 1a7.6 7.6 0 0 0-2.6-1.5L14 2.5h-4l-.4 2.6a7.6 7.6 0 0 0-2.6 1.5l-2.4-1-2 3.4 2 1.5a7.6 7.6 0 0 0 0 3l-2 1.5 2 3.4 2.4-1a7.6 7.6 0 0 0 2.6 1.5l.4 2.6h4l.4-2.6a7.6 7.6 0 0 0 2.6-1.5l2.4 1 2-3.4z" />
    </svg>
  );
}

function ListIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M9 6h11M9 12h11M9 18h11" strokeLinecap="round" />
      <circle cx="4.5" cy="6" r="1" />
      <circle cx="4.5" cy="12" r="1" />
      <circle cx="4.5" cy="18" r="1" />
    </svg>
  );
}

function LogoutIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="M16 17l5-5-5-5M21 12H9" />
    </svg>
  );
}

function MenuIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M4 6h16M4 12h16M4 18h16" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

function MapPinIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 21s7-6.4 7-12a7 7 0 0 0-14 0c0 5.6 7 12 7 12Z" />
      <circle cx="12" cy="9" r="2.4" />
    </svg>
  );
}

function AlertIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3.5 2.5 20h19L12 3.5Z" />
      <path d="M12 10v4.5M12 17.5h.01" />
    </svg>
  );
}

function BusIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3.5" y="4" width="17" height="13" rx="2.5" />
      <path d="M3.5 11h17M7 20v-3M17 20v-3" />
      <circle cx="7.5" cy="14" r="0.6" />
      <circle cx="16.5" cy="14" r="0.6" />
    </svg>
  );
}

function ClipboardIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="5" y="4.5" width="14" height="16.5" rx="2" />
      <path d="M9 4.5h6v2.5H9zM8.5 12h7M8.5 16h5" />
    </svg>
  );
}

function ChevronIcon({ collapsed }: { collapsed: boolean }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="transition-transform duration-300 ease-out"
      style={{ transform: collapsed ? 'rotate(180deg)' : 'none' }}
    >
      <path d="M15 6l-6 6 6 6" />
    </svg>
  );
}

/** Who's currently signed in — an initial avatar + name, next to the
 * notification bell in both header bars, so it's obvious at a glance
 * which admin is using the site (useful once more than one exists). */
function AdminIdentity({ light = false }: { light?: boolean }) {
  const { admin } = useAuth();
  if (!admin) return null;
  const initial = admin.fullName.trim().charAt(0).toUpperCase() || '?';

  return (
    <div className="flex items-center gap-2" title={admin.email}>
      <div
        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-bold ${
          light ? 'bg-white text-brand-blue' : 'bg-brand-blue text-white'
        }`}
      >
        {initial}
      </div>
      <span
        className={`hidden max-w-[10rem] truncate text-sm font-medium sm:inline ${light ? 'text-white' : 'text-gray-700'}`}
      >
        {admin.fullName}
      </span>
    </div>
  );
}

// `groupStart` gets each item extra top margin instead of a visible
// divider line — quiet breathing room between Overview/Fleet/People/
// System clusters rather than another hard rule to render.
// [roles] limits an item to those roles (absent = everyone). The backend
// enforces access independently; this only hides what a role can't open.
// Operators see just their own fleet: Operations, Fleet, Short-Tripping,
// Incident Reports, Fleet Reports and Settings.
interface NavItem {
  to: string;
  label: string;
  icon: () => ReactNode;
  end: boolean;
  groupStart: boolean;
  roles?: AdminRole[];
}

const ADMIN_LEVEL: AdminRole[] = ['MAIN_ADMIN', 'ADMIN'];
const NOT_OPERATOR: AdminRole[] = ['MAIN_ADMIN', 'ADMIN', 'MANIBELA'];

const navItems: NavItem[] = [
  { to: '/', label: 'Dashboard', icon: GridIcon, end: true, groupStart: false, roles: NOT_OPERATOR },
  { to: '/operations', label: 'Operations', icon: ClipboardIcon, end: false, groupStart: false },
  { to: '/fleet', label: 'Fleet', icon: BusIcon, end: false, groupStart: false },
  { to: '/short-tripping', label: 'Short-Tripping', icon: AlertIcon, end: false, groupStart: false },
  { to: '/jeepney-monitoring', label: 'Jeepney Monitoring', icon: RouteIcon, end: false, groupStart: true, roles: NOT_OPERATOR },
  { to: '/passenger-monitoring', label: 'Passenger Monitoring', icon: MapPinIcon, end: false, groupStart: false, roles: NOT_OPERATOR },
  { to: '/drivers', label: 'Drivers', icon: SteeringWheelIcon, end: false, groupStart: true, roles: NOT_OPERATOR },
  { to: '/commuters', label: 'Commuters', icon: PeopleIcon, end: false, groupStart: false, roles: NOT_OPERATOR },
  { to: '/id-verification', label: 'ID Verification', icon: BadgeCheckIcon, end: false, groupStart: false, roles: NOT_OPERATOR },
  { to: '/incident-reports', label: 'Incident Reports', icon: AlertIcon, end: false, groupStart: false },
  { to: '/fleet-reports', label: 'Fleet Reports', icon: ReportIcon, end: false, groupStart: true },
  { to: '/reports', label: 'Earnings Log Report', icon: ReportIcon, end: false, groupStart: false, roles: NOT_OPERATOR },
  { to: '/app-content', label: 'IDs & Hotlines', icon: ListIcon, end: false, groupStart: false, roles: ADMIN_LEVEL },
  { to: '/settings', label: 'Settings', icon: GearIcon, end: false, groupStart: false },
];

function navItemsFor(role?: AdminRole): NavItem[] {
  return navItems.filter((item) => !item.roles || (role !== undefined && item.roles.includes(role)));
}

function isNavItemActive(pathname: string, to: string, end: boolean): boolean {
  return end ? pathname === to : pathname === to || pathname.startsWith(`${to}/`);
}

function SidebarContent({ onNavigate, collapsed = false }: { onNavigate?: () => void; collapsed?: boolean }) {
  const { admin, logout } = useAuth();
  const [confirmingLogout, setConfirmingLogout] = useState(false);
  const { pathname } = useLocation();
  const items = navItemsFor(admin?.role);
  const activeIndex = items.findIndex(({ to, end }) => isNavItemActive(pathname, to, end));

  // The sliding pill is positioned from the active row's real measured
  // box, not from hard-coded row heights, so it always lines up with the
  // item (whatever the role's item list, group spacing or font rendering).
  const navRef = useRef<HTMLElement>(null);
  const itemRefs = useRef<(HTMLAnchorElement | null)[]>([]);
  const [pill, setPill] = useState<{ top: number; height: number } | null>(null);
  useLayoutEffect(() => {
    const measure = () => {
      const el = itemRefs.current[activeIndex];
      setPill(el ? { top: el.offsetTop, height: el.offsetHeight } : null);
    };
    measure();
    const nav = navRef.current;
    if (!nav || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(measure);
    observer.observe(nav);
    return () => observer.disconnect();
  }, [activeIndex, items.length, collapsed]);

  return (
    <>
      {/* Logo centered in its own row — previously it sat alone at the
          left with a big dead gap before the corner chevron (that used to
          balance against the "Admin" label, since removed). Centering it
          reads as deliberate branding instead. */}
      <div className="relative flex items-center justify-center py-6">
        <LogoMark size={68} />
      </div>

      <nav ref={navRef} className="relative mt-2 flex flex-1 flex-col gap-0.5 overflow-y-auto px-3">
        {/* Sliding active-indicator — one shared pill that moves between
            rows instead of each row instantly swapping its own
            background, so navigating reads as continuous motion. */}
        {pill && (
          <div
            className="absolute left-3 right-3 rounded-lg bg-brand-blue shadow-sm transition-[top,height] duration-300 ease-out"
            style={{ top: pill.top, height: pill.height }}
          />
        )}
        {items.map(({ to, label, icon: Icon, end, groupStart }, i) => (
          <NavLink
            key={to}
            ref={(el) => {
              itemRefs.current[i] = el;
            }}
            to={to}
            end={end}
            onClick={onNavigate}
            title={collapsed ? label : undefined}
            className={({ isActive }) =>
              `relative z-10 flex h-11 shrink-0 items-center gap-3 rounded-lg px-3.5 text-sm font-medium transition-colors duration-150 ${
                collapsed ? 'justify-center px-0' : ''
              } ${groupStart ? 'mt-3.5' : ''} ${
                isActive ? 'text-white' : 'text-white/65 hover:bg-white/10 hover:text-white'
              }`
            }
          >
            <Icon />
            {!collapsed && label}
          </NavLink>
        ))}
      </nav>

      <div className="border-t border-white/10 px-4 py-4">
        {!collapsed && <p className="truncate px-2 text-xs text-white/45">{admin?.email}</p>}
        <button
          onClick={() => setConfirmingLogout(true)}
          title={collapsed ? 'Log Out' : undefined}
          className={`mt-2 flex w-full items-center gap-3 rounded-lg px-3.5 py-2.5 text-sm font-medium text-white/65 transition-colors duration-150 hover:bg-status-critical/15 hover:text-white ${
            collapsed ? 'justify-center px-0' : ''
          }`}
        >
          <LogoutIcon />
          {!collapsed && 'Log Out'}
        </button>
      </div>

      {confirmingLogout && (
        <LogoutConfirmDialog onCancel={() => setConfirmingLogout(false)} onConfirm={logout} />
      )}
    </>
  );
}

const COLLAPSE_STORAGE_KEY = 'adminSidebarCollapsed';

export function DashboardLayout({ children, title }: { children: ReactNode; title?: string }) {
  const navigate = useNavigate();
  const { admin } = useAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(COLLAPSE_STORAGE_KEY) === 'true');

  useEffect(() => {
    localStorage.setItem(COLLAPSE_STORAGE_KEY, String(collapsed));
  }, [collapsed]);

  // Fetched/polled exactly once here (not inside NotificationBell, which
  // renders twice — once per responsive header) and handed down, so
  // there's a single source of truth for the badge and exactly one toast
  // per arriving notification instead of one per header.
  const { notifications, unreadCount, markAllRead, toasts, dismissToast, hasNextPage, isLoadingMore, loadMore } =
    useAdminNotificationFeed(admin?.role !== 'OPERATOR');

  const handleToastClick = (n: AdminNotification) => {
    dismissToast(n.id);
    const path = adminNotificationPath(n);
    if (!path) return;
    navigate(path);
  };

  return (
    <div className="min-h-screen bg-surface-page">
      {/* Toast layer — fixed to the viewport, rendered once regardless of
          which page or header breakpoint is active. */}
      <div className="pointer-events-none fixed right-4 top-20 z-50 flex w-80 max-w-[90vw] flex-col gap-2">
        {toasts.map((n) => {
          const isNavigable = !!adminNotificationPath(n);
          return (
            <div
              key={n.id}
              onClick={isNavigable ? () => handleToastClick(n) : undefined}
              className={`pointer-events-auto rounded-xl border border-gray-200 bg-white p-4 shadow-lg ring-1 ring-black/5 ${
                isNavigable ? 'cursor-pointer hover:border-brand-blue' : ''
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="h-2 w-2 flex-shrink-0 rounded-full bg-brand-blue" />
                  <p className="text-sm font-semibold text-gray-900">{n.title}</p>
                </div>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    dismissToast(n.id);
                  }}
                  className="rounded p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
                  aria-label="Dismiss notification"
                >
                  <CloseIcon />
                </button>
              </div>
              <p className="mt-1 whitespace-pre-line text-xs text-gray-600">{n.message}</p>
            </div>
          );
        })}
      </div>

      {/* Desktop sidebar — permanent column at lg+, collapsible to an
          icon-only rail via the floating circle button on its edge. */}
      <aside
        className={`fixed inset-y-0 left-0 z-30 hidden flex-col border-r border-black/10 bg-gradient-to-b from-[#111c4d] via-ink to-black transition-[width] duration-200 lg:flex ${
          collapsed ? 'w-20' : 'w-64'
        }`}
      >
        <SidebarContent collapsed={collapsed} />
        <button
          onClick={() => setCollapsed((v) => !v)}
          className="absolute -right-3 top-16 flex h-6 w-6 items-center justify-center rounded-full border border-black/10 bg-white text-gray-500 shadow-sm transition hover:text-brand-blue"
          aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          <ChevronIcon collapsed={collapsed} />
        </button>
      </aside>

      {/* Mobile sidebar — slide-over drawer. Always mounted (not
          conditionally rendered) so the transitions below actually have
          something to animate on close, not just an instant unmount. */}
      <div
        className={`fixed inset-0 z-40 lg:hidden ${mobileOpen ? 'pointer-events-auto' : 'pointer-events-none'}`}
        aria-hidden={!mobileOpen}
      >
        {/* Inline transition styles here, not Tailwind's duration and ease
            utilities — in Tailwind v4, transition-opacity and transition-
            transform bundle their own default duration+timing, which won
            the cascade over the duration-300/ease-in-out classes and made
            both of these snap open in ~30ms instead of the intended
            300ms (confirmed by polling getComputedStyle().transitionDuration
            mid-animation: it read 0.2s, not 300ms). Inline style has no
            such conflict. */}
        <div
          className={`absolute inset-0 bg-black/40 ${mobileOpen ? 'opacity-100' : 'opacity-0'}`}
          style={{ transition: 'opacity 300ms ease-in-out' }}
          onClick={() => setMobileOpen(false)}
        />
        <aside
          className={`absolute inset-y-0 left-0 flex w-72 flex-col overflow-hidden bg-gradient-to-b from-[#111c4d] via-ink to-black shadow-xl ${
            mobileOpen ? 'translate-x-0' : '-translate-x-full'
          }`}
          // Tailwind v4's translate-x-* utilities animate the standalone
          // CSS `translate` property, not `transform` — transitioning
          // `transform` here was a no-op since it never actually changes.
          style={{ transition: 'translate 300ms ease-in-out' }}
        >
          <button
            onClick={() => setMobileOpen(false)}
            className="absolute right-3 top-4 z-10 rounded-lg p-1.5 text-white/60 hover:bg-white/10 hover:text-white"
            aria-label="Close menu"
          >
            <CloseIcon />
          </button>
          <SidebarContent onNavigate={() => setMobileOpen(false)} />
        </aside>
      </div>

      {/* Mobile top bar */}
      <header className="relative sticky top-0 z-20 flex items-center gap-3 bg-gradient-to-r from-[#111c4d] via-ink to-black px-4 py-3 shadow-[0_1px_3px_rgba(16,24,40,0.12)] lg:hidden">
        <button
          onClick={() => setMobileOpen(true)}
          className="relative rounded-lg p-1.5 text-white hover:bg-white/15"
          aria-label="Open menu"
        >
          <MenuIcon />
        </button>
        <LogoMark size={28} />
        <span className="relative font-display text-sm font-bold text-white">ManibelApp Admin</span>
        <div className="relative ml-auto flex items-center gap-3">
          <AdminIdentity light />
          <NotificationBell
            notifications={notifications}
            unreadCount={unreadCount}
            onMarkAllRead={markAllRead}
            hasNextPage={hasNextPage}
            isLoadingMore={isLoadingMore}
            onLoadMore={loadMore}
            light
          />
        </div>
      </header>

      <main className={`transition-[padding] duration-200 ${collapsed ? 'lg:pl-20' : 'lg:pl-64'}`}>
        {/* Desktop top bar — the mobile header above already carries the
            bell, so this is lg-only to avoid rendering it twice. Title on
            the left mirrors whatever <h1> the page itself renders below,
            so there's still page context once you've scrolled past it. */}
        <div className="sticky top-0 z-20 relative hidden items-center justify-between gap-3 bg-gradient-to-r from-[#111c4d] via-ink to-black px-4 py-3 shadow-[0_1px_3px_rgba(16,24,40,0.12)] lg:flex lg:px-8">
          <h2 className="relative truncate font-display text-sm font-semibold text-white">{title}</h2>
          <div className="relative flex items-center gap-3">
            <AdminIdentity light />
            <NotificationBell
              notifications={notifications}
              unreadCount={unreadCount}
              onMarkAllRead={markAllRead}
              hasNextPage={hasNextPage}
              isLoadingMore={isLoadingMore}
              onLoadMore={loadMore}
              light
            />
          </div>
        </div>
        <div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">{children}</div>
      </main>
    </div>
  );
}
