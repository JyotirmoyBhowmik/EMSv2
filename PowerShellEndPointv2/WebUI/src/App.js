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
import ResultsHistory from './components/ResultsHistory';
import Login from './components/Login';

function Computers() {
    return (
        <div>
            <h1 style={{ marginBottom: '20px' }}>Computers</h1>
            <div className="card">Computers page placeholder.</div>
        </div>
    );
}

function MetricsExplorer() {
    return (
        <div>
            <h1 style={{ marginBottom: '20px' }}>Metrics Explorer</h1>
            <div className="card">Metrics Explorer page placeholder.</div>
        </div>
    );
}

function getStoredUser() {
    try {
        const userJson = localStorage.getItem('user');
        return userJson ? JSON.parse(userJson) : null;
    } catch {
        return null;
    }
}

function getPermissions(user) {
    const perms = user?.permissions || {};
    return {
        canView: perms.canView !== false,
        canScan: perms.canScan === true,
        canArchive: perms.canArchive === true,
        canAdmin: perms.canAdmin === true
    };
}

function ProtectedRoute({ children, requireScan = false, requireAdmin = false }) {
    const location = useLocation();
    const token = localStorage.getItem('auth_token');
    const user = getStoredUser();
    const permissions = getPermissions(user);

    if (!token || !user) {
        return <Navigate to="/login" replace state={{ from: location }} />;
    }

    if (!permissions.canView) {
        return <Navigate to="/login" replace />;
    }

    if (requireScan && !permissions.canScan) {
        return <Navigate to="/dashboard" replace />;
    }

    if (requireAdmin && !permissions.canAdmin) {
        return <Navigate to="/dashboard" replace />;
    }

    return children;
}

function Layout() {
    const user = getStoredUser();
    const permissions = getPermissions(user);

    const navLinkStyle = ({ isActive }) => ({
        display: 'flex',
        alignItems: 'center',
        gap: '10px',
        padding: '12px 14px',
        color: isActive ? '#ffffff' : 'rgba(255,255,255,0.85)',
        textDecoration: 'none',
        borderRadius: '8px',
        background: isActive ? 'rgba(255,255,255,0.12)' : 'transparent',
        fontWeight: isActive ? 600 : 500,
        marginBottom: '6px'
    });

    const displayName = user?.displayName || user?.username || 'User';

    const handleLogout = () => {
        localStorage.removeItem('auth_token');
        localStorage.removeItem('user');
        localStorage.removeItem('authProvider');
        window.location.href = '/login';
    };

    return (
        <div style={{ display: 'flex', minHeight: '100vh', background: '#f5f7fb' }}>
            <aside
                style={{
                    width: '280px',
                    background: '#1f2a6d',
                    color: '#fff',
                    padding: '22px 18px'
                }}
            >
                <div style={{ fontSize: '1.25rem', fontWeight: 700, marginBottom: '20px' }}>
                    Endpoint Monitoring System
                </div>

                <nav>
                    <NavLink to="/dashboard" style={navLinkStyle}>Dashboard</NavLink>
                    <NavLink to="/results?view=daily" style={navLinkStyle}>Daily Monitoring</NavLink>
                    <NavLink to="/results?view=compliance" style={navLinkStyle}>Compliance Report</NavLink>
                    <NavLink to="/results" style={navLinkStyle}>Results History</NavLink>

                    {permissions.canAdmin && (
                        <>
                            <NavLink to="/computers" style={navLinkStyle}>Computers</NavLink>
                            <NavLink to="/metrics" style={navLinkStyle}>Metrics Explorer</NavLink>
                        </>
                    )}

                    {permissions.canScan && (
                        <NavLink to="/scan" style={navLinkStyle}>Scan Endpoint</NavLink>
                    )}
                </nav>
            </aside>

            <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
                <header
                    style={{
                        background: '#ffffff',
                        borderBottom: '1px solid #e5e7eb',
                        padding: '14px 24px',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center'
                    }}
                >
                    <div style={{ fontWeight: 600 }}>Endpoint Monitoring System</div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                        <span>Welcome {displayName}</span>
                        <span
                            style={{
                                background: permissions.canAdmin ? '#e8f5e9' : '#eef2ff',
                                color: permissions.canAdmin ? '#2e7d32' : '#1e3a8a',
                                padding: '4px 10px',
                                borderRadius: '999px',
                                fontSize: '0.85rem',
                                fontWeight: 600
                            }}
                        >
                            {user?.role || 'Viewer'}
                        </span>
                        <button className="btn btn-secondary" onClick={handleLogout}>Logout</button>
                    </div>
                </header>

                <main style={{ padding: '24px' }}>
                    <Outlet />
                </main>
            </div>
        </div>
    );
}

function AppRoutes() {
    const [loginTick, setLoginTick] = useState(0);

    const handleLogin = () => {
        setLoginTick((v) => v + 1);
    };

    return (
        <Routes>
            <Route
                path="/login"
                element={
                    localStorage.getItem('auth_token') ? (
                        <Navigate to="/dashboard" replace />
                    ) : (
                        <Login onLogin={handleLogin} />
                    )
                }
            />

            <Route
                path="/"
                element={
                    <ProtectedRoute>
                        <Layout key={loginTick} />
                    </ProtectedRoute>
                }
            >
                <Route index element={<Navigate to="/dashboard" replace />} />
                <Route path="dashboard" element={<Dashboard />} />
                <Route
                    path="scan"
                    element={
                        <ProtectedRoute requireScan={true}>
                            <ScanEndpoint />
                        </ProtectedRoute>
                    }
                />
                <Route path="results" element={<ResultsHistory />} />
                <Route
                    path="computers"
                    element={
                        <ProtectedRoute requireAdmin={true}>
                            <Computers />
                        </ProtectedRoute>
                    }
                />
                <Route
                    path="metrics"
                    element={
                        <ProtectedRoute requireAdmin={true}>
                            <MetricsExplorer />
                        </ProtectedRoute>
                    }
                />
            </Route>

            <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
    );
}

function App() {
    return (
        <Router>
            <AppRoutes />
        </Router>
    );
}

export default App;
