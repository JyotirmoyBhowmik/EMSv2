import React, { useState } from 'react';
import {
    BrowserRouter as Router,
    Routes,
    Route,
    NavLink,
    Navigate,
    Outlet,
    useLocation
} from 'react-router-dom';
import Dashboard from './components/Dashboard';
import ScanEndpoint from './components/ScanEndpoint';
import ScanTrace from './components/ScanTrace';
import ComplianceReport from './components/ComplianceReport';
import ResultsHistory from './components/ResultsHistory';
import Login from './components/Login';
import AdminSettings from './components/AdminSettings';
import AuditLog from './components/AuditLog';
import RebootDashboard from './components/RebootDashboard';
import ConnectorHealth from './components/ConnectorHealth';
import UserManagement from './components/UserManagement';
import EndpointLifecycle from './components/EndpointLifecycle';
import SystemErrors from './components/SystemErrors';
import ChangePasswordModal from './components/ChangePasswordModal';
import HistoricalReports from './components/HistoricalReports';
import ScanStatus from './components/ScanStatus';

// ─── Nav icons (inline SVG, no extra dep) ───────────
const Icons = {
    Dashboard:  () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/></svg>,
    Monitor:    () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M21 3H3c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H3V5h18v14z"/></svg>,
    Results:    () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z"/></svg>,
    Scan:       () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M15.5 14h-.79l-.28-.27A6.471 6.471 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>,
    Settings:   () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.07-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.07,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.07-0.47-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>,
    Users:      () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/></svg>,
    Endpoints:  () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm-5 11H4v-2h11v2zm3-4H4V9h14v2z"/></svg>,
    Reboot:     () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg>,
    Health:     () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>,
    Errors:     () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>,
    Audit:      () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 3c1.93 0 3.5 1.57 3.5 3.5S13.93 13 12 13s-3.5-1.57-3.5-3.5S10.07 6 12 6zm7 13H5v-.23c0-.62.28-1.2.76-1.58C7.47 15.82 9.64 15 12 15s4.53.82 6.24 2.19c.48.38.76.97.76 1.58V19z"/></svg>,
    Logout:     () => <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/></svg>
};

function getStoredUser() {
    try { return JSON.parse(localStorage.getItem('user') || 'null'); } catch { return null; }
}

function getPermissions(user) {
    const p = user?.permissions || {};
    return {
        canView:    p.canView    !== false,
        canScan:    p.canScan    === true,
        canArchive: p.canArchive === true,
        canAdmin:   p.canAdmin   === true
    };
}

function ProtectedRoute({ children, requireScan = false, requireAdmin = false }) {
    const location = useLocation();
    const token = localStorage.getItem('auth_token');
    const user  = getStoredUser();
    const perms = getPermissions(user);

    if (!token || !user)     return <Navigate to="/login" replace state={{ from: location }} />;
    if (!perms.canView)      return <Navigate to="/login" replace />;
    if (requireScan   && !perms.canScan)  return <Navigate to="/dashboard" replace />;
    if (requireAdmin  && !perms.canAdmin) return <Navigate to="/dashboard" replace />;

    return children;
}

function NavItem({ to, icon: Icon, label, end = false }) {
    const location = useLocation();
    
    // Parse the path and search from the 'to' prop
    const toPath = to.split('?')[0];
    const toSearch = to.split('?')[1] || '';
    
    // Check if the path matches
    const pathMatches = end ? location.pathname === toPath : location.pathname.startsWith(toPath);
    
    // If it's the results path, we must match the view query parameter exactly
    let isQueryMatch = true;
    if (toPath === '/results') {
        const currentParams = new URLSearchParams(location.search);
        const toParams = new URLSearchParams(toSearch);
        const currentView = currentParams.get('view') || '';
        const toView = toParams.get('view') || '';
        isQueryMatch = currentView === toView;
    }

    const isActive = pathMatches && isQueryMatch;

    return (
        <NavLink
            to={to}
            end={end}
            style={() => ({
                display: 'flex', alignItems: 'center', gap: '10px',
                padding: '10px 14px', color: isActive ? '#ffffff' : 'rgba(255,255,255,0.75)',
                textDecoration: 'none', borderRadius: '8px', fontSize: '0.875rem',
                background: isActive ? 'rgba(99,179,237,0.2)' : 'transparent',
                borderLeft: isActive ? '3px solid #63b3ed' : '3px solid transparent',
                fontWeight: isActive ? 600 : 400, marginBottom: '2px',
                transition: 'all 0.15s ease'
            })}
        >
            <Icon />
            {label}
        </NavLink>
    );
}

function NavSection({ label }) {
    return (
        <div style={{
            padding: '16px 14px 6px', fontSize: '0.7rem',
            textTransform: 'uppercase', color: 'rgba(255,255,255,0.35)',
            fontWeight: 700, letterSpacing: '1.2px'
        }}>
            {label}
        </div>
    );
}

function Layout() {
    const user  = getStoredUser();
    const perms = getPermissions(user);
    const displayName = user?.displayName || user?.username || 'User';
    const isAdmin = perms.canAdmin;
    const [isPasswordModalOpen, setIsPasswordModalOpen] = useState(false);

    const handleLogout = () => {
        localStorage.removeItem('auth_token');
        localStorage.removeItem('user');
        localStorage.removeItem('authProvider');
        window.location.href = '/login';
    };

    return (
        <div style={{ display: 'flex', minHeight: '100vh', background: '#f0f4f8', fontFamily: "'Inter', 'Segoe UI', sans-serif" }}>
            {/* ── Sidebar ── */}
            <aside style={{
                width: '260px', flexShrink: 0,
                background: 'linear-gradient(180deg, #1a1f3c 0%, #0f1729 100%)',
                color: '#fff', display: 'flex', flexDirection: 'column',
                boxShadow: '4px 0 20px rgba(0,0,0,0.3)', zIndex: 10
            }}>
                {/* Logo */}
                <div style={{ padding: '24px 20px 20px', borderBottom: '1px solid rgba(255,255,255,0.08)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                        <div style={{
                            width: 36, height: 36, borderRadius: '10px',
                            background: 'linear-gradient(135deg, #3b82f6, #1d4ed8)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            fontSize: '1.1rem', fontWeight: 800, color: '#fff'
                        }}>E</div>
                        <div>
                            <div style={{ fontSize: '0.9rem', fontWeight: 700, lineHeight: 1.2 }}>EMS Enterprise</div>
                            <div style={{ fontSize: '0.7rem', color: 'rgba(255,255,255,0.45)', marginTop: 2 }}>v5.0.0-Enterprise · Monitoring</div>
                        </div>
                    </div>
                </div>

                {/* Navigation */}
                <nav style={{ padding: '12px 10px', flex: 1, overflowY: 'auto' }}>
                    <NavSection label="Monitoring" />
                    <NavItem to="/dashboard"               icon={Icons.Dashboard} label="Dashboard"         end />
                    <NavItem to="/results?view=daily"      icon={Icons.Monitor}   label="Daily Monitoring" />
                    <NavItem to="/results?view=compliance" icon={Icons.Results}   label="Compliance Report" />
                    <NavItem to="/reports"                 icon={Icons.Audit}     label="Advanced Reports" />
                    <NavItem to="/results"                 icon={Icons.Results}   label="Results History"  />

                    {perms.canScan && (
                        <>
                            <NavSection label="Operations" />
                            <NavItem to="/scan" icon={Icons.Scan} label="Scan Endpoint" />
                        </>
                    )}

                    {isAdmin && (
                        <>
                            <NavSection label="Administration" />
                            <NavItem to="/admin/settings"  icon={Icons.Settings}  label="Settings & Features" />
                            <NavItem to="/admin/users"     icon={Icons.Users}     label="User Management" />
                            <NavItem to="/admin/endpoints" icon={Icons.Endpoints} label="Endpoint Lifecycle" />
                            <NavItem to="/admin/reboot"    icon={Icons.Reboot}    label="Reboot Monitoring" />
                            <NavItem to="/admin/health"    icon={Icons.Health}    label="Connector Health" />
                            <NavItem to="/admin/errors"    icon={Icons.Errors}    label="System Errors" />
                            <NavItem to="/admin/audit"     icon={Icons.Audit}     label="Audit Logs" />
                        </>
                    )}
                </nav>

                {/* User footer */}
                <div style={{ padding: '14px 18px', borderTop: '1px solid rgba(255,255,255,0.08)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: 10 }}>
                        <div style={{
                            width: 34, height: 34, borderRadius: '50%',
                            background: isAdmin ? 'linear-gradient(135deg,#16a34a,#4ade80)' : 'linear-gradient(135deg,#2563eb,#60a5fa)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            fontSize: '0.85rem', fontWeight: 700, color: '#fff', flexShrink: 0
                        }}>
                            {displayName.charAt(0).toUpperCase()}
                        </div>
                        <div style={{ overflow: 'hidden' }}>
                            <div style={{ fontSize: '0.82rem', fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                {displayName}
                            </div>
                            <div style={{
                                fontSize: '0.7rem', marginTop: 2,
                                color: isAdmin ? '#4ade80' : '#93c5fd',
                                fontWeight: 600
                            }}>
                                {user?.role || 'Viewer'}
                            </div>
                        </div>
                    </div>
                    <button
                        onClick={() => setIsPasswordModalOpen(true)}
                        style={{
                            width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center',
                            gap: 8, padding: '8px 12px', border: '1px solid rgba(255,255,255,0.15)',
                            borderRadius: 8, background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.7)',
                            cursor: 'pointer', fontSize: '0.8rem', fontWeight: 500,
                            transition: 'all 0.15s ease', marginBottom: 8
                        }}
                        onMouseOver={e => { e.currentTarget.style.background='rgba(255,255,255,0.12)'; e.currentTarget.style.color='#fff'; }}
                        onMouseOut={e => { e.currentTarget.style.background='rgba(255,255,255,0.06)'; e.currentTarget.style.color='rgba(255,255,255,0.7)'; }}
                    >
                        <Icons.Users /> Change Password
                    </button>

                    <button
                        onClick={handleLogout}
                        style={{
                            width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center',
                            gap: 8, padding: '8px 12px', border: '1px solid rgba(255,255,255,0.15)',
                            borderRadius: 8, background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.7)',
                            cursor: 'pointer', fontSize: '0.8rem', fontWeight: 500,
                            transition: 'all 0.15s ease'
                        }}
                        onMouseOver={e => { e.currentTarget.style.background='rgba(255,255,255,0.12)'; e.currentTarget.style.color='#fff'; }}
                        onMouseOut={e => { e.currentTarget.style.background='rgba(255,255,255,0.06)'; e.currentTarget.style.color='rgba(255,255,255,0.7)'; }}
                    >
                        <Icons.Logout /> Sign Out
                    </button>
                </div>
            </aside>

            {/* ── Main content ── */}
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
                {/* Topbar */}
                <header style={{
                    background: '#ffffff', borderBottom: '1px solid #e2e8f0',
                    padding: '0 28px', height: 60, display: 'flex',
                    justifyContent: 'space-between', alignItems: 'center',
                    boxShadow: '0 1px 4px rgba(0,0,0,0.06)', flexShrink: 0
                }}>
                    <div style={{ fontSize: '0.95rem', fontWeight: 600, color: '#1e293b' }}>
                        Enterprise Endpoint Monitoring System
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                        <div style={{
                            width: 8, height: 8, borderRadius: '50%',
                            background: '#22c55e', boxShadow: '0 0 6px #22c55e'
                        }} title="API Connected" />
                        <span style={{ fontSize: '0.8rem', color: '#64748b' }}>Live</span>
                    </div>
                </header>

                <main style={{ flex: 1, padding: '28px', overflowY: 'auto' }}>
                    <Outlet />
                </main>
            </div>

            <ChangePasswordModal 
                isOpen={isPasswordModalOpen} 
                onClose={() => setIsPasswordModalOpen(false)} 
            />
        </div>
    );
}

function AppRoutes() {
    const [loginTick, setLoginTick] = useState(0);

    return (
        <Routes>
            <Route
                path="/login"
                element={
                    localStorage.getItem('auth_token')
                        ? <Navigate to="/dashboard" replace />
                        : <Login onLogin={() => setLoginTick(v => v + 1)} />
                }
            />

            <Route path="/" element={<ProtectedRoute><Layout key={loginTick} /></ProtectedRoute>}>
                <Route index element={<Navigate to="/dashboard" replace />} />
                <Route path="dashboard" element={<Dashboard />} />
                <Route path="results"   element={<ResultsHistory />} />
                <Route path="compliance" element={<ComplianceReport />} />
                <Route path="reports"    element={<HistoricalReports />} />
                <Route path="scan/trace/:scanId" element={<ScanTrace />} />
                <Route path="scan/status/:scanId" element={<ScanStatus />} />

                <Route path="scan" element={
                    <ProtectedRoute requireScan>
                        <ScanEndpoint />
                    </ProtectedRoute>
                } />

                {/* Admin routes */}
                <Route path="admin/settings"  element={<ProtectedRoute requireAdmin><AdminSettings /></ProtectedRoute>} />
                <Route path="admin/users"     element={<ProtectedRoute requireAdmin><UserManagement /></ProtectedRoute>} />
                <Route path="admin/endpoints" element={<ProtectedRoute requireAdmin><EndpointLifecycle /></ProtectedRoute>} />
                <Route path="admin/reboot"    element={<ProtectedRoute requireAdmin><RebootDashboard /></ProtectedRoute>} />
                <Route path="admin/health"    element={<ProtectedRoute requireAdmin><ConnectorHealth /></ProtectedRoute>} />
                <Route path="admin/errors"    element={<ProtectedRoute requireAdmin><SystemErrors /></ProtectedRoute>} />
                <Route path="admin/audit"     element={<ProtectedRoute requireAdmin><AuditLog /></ProtectedRoute>} />
            </Route>

            <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
    );
}

function App() {
    return (
        <Router future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
            <AppRoutes />
        </Router>
    );
}

export default App;
