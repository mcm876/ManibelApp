import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Navigate } from 'react-router-dom';
import { AuthProvider, ProtectedRoute, useAuth, type AdminRole } from './lib/auth';
import LoginPage from './pages/LoginPage';
import ForgotPasswordPage from './pages/ForgotPasswordPage';
import DashboardPage from './pages/DashboardPage';
import DriversPage from './pages/DriversPage';
import CommutersPage from './pages/CommutersPage';
import CommuterDetailPage from './pages/CommuterDetailPage';
import IdVerificationPage from './pages/IdVerificationPage';
import JeepneyMonitoringPage from './pages/JeepneyMonitoringPage';
import JeepneyLiveMapPage from './pages/JeepneyLiveMapPage';
import TripHistoryPage from './pages/TripHistoryPage';
import PassengerMonitoringPage from './pages/PassengerMonitoringPage';
import PassengerLiveMapPage from './pages/PassengerLiveMapPage';
import IncidentReportsPage from './pages/IncidentReportsPage';
import ReportsPage from './pages/ReportsPage';
import SettingsPage from './pages/SettingsPage';
import AppContentPage from './pages/AppContentPage';
import OperationsPage from './pages/OperationsPage';
import FleetPage from './pages/FleetPage';
import ShortTrippingPage from './pages/ShortTrippingPage';
import FleetReportsPage from './pages/FleetReportsPage';

// Pages built for administrators/MANIBELA that return every operator's data —
// operators are fenced out here and, independently, on the backend.
const NOT_OPERATOR: AdminRole[] = ['MAIN_ADMIN', 'ADMIN', 'MANIBELA'];
const ADMIN_LEVEL: AdminRole[] = ['MAIN_ADMIN', 'ADMIN'];

function Home() {
  const { admin } = useAuth();
  // Operators have no association-wide dashboard; their home is Operations.
  if (admin?.role === 'OPERATOR') return <Navigate to="/operations" replace />;
  return <DashboardPage />;
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route path="/forgot-password" element={<ForgotPasswordPage />} />

          <Route
            path="/"
            element={
              <ProtectedRoute>
                <Home />
              </ProtectedRoute>
            }
          />
          <Route
            path="/operations"
            element={
              <ProtectedRoute>
                <OperationsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/fleet"
            element={
              <ProtectedRoute>
                <FleetPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/short-tripping"
            element={
              <ProtectedRoute>
                <ShortTrippingPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/fleet-reports"
            element={
              <ProtectedRoute>
                <FleetReportsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/jeepney-monitoring"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <JeepneyMonitoringPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/jeepney-monitoring/map"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <JeepneyLiveMapPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/jeepney-monitoring/history"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <TripHistoryPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/passenger-monitoring"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <PassengerMonitoringPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/passenger-monitoring/map"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <PassengerLiveMapPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/drivers"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <DriversPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/commuters"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <CommutersPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/commuters/:id"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <CommuterDetailPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/id-verification"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <IdVerificationPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/incident-reports"
            element={
              <ProtectedRoute>
                <IncidentReportsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/reports"
            element={
              <ProtectedRoute roles={NOT_OPERATOR}>
                <ReportsPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/app-content"
            element={
              <ProtectedRoute roles={ADMIN_LEVEL}>
                <AppContentPage />
              </ProtectedRoute>
            }
          />
          <Route
            path="/settings"
            element={
              <ProtectedRoute>
                <SettingsPage />
              </ProtectedRoute>
            }
          />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}
