import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { dashboardService } from '../services/api';

function Dashboard() {
    const navigate = useNavigate();

    const [stats, setStats] = useState({
        totalScans: 0,
        healthyEndpoints: 0,
        criticalAlerts: 0,
        uniqueEndpoints: 0,
        completedScans: 0,
        failedScans: 0,
        inProgressScans: 0,
        averageScanTime: null,
        lastScan: null,
        excellentCount: 0,
        goodCount: 0,
        fairCount: 0,
        poorCount: 0,
        totalComputers: 0,
        activeComputers: 0,
        compliantEndpoints: 0,
        partialCompliantEndpoints: 0,
        collectionFailedEndpoints: 0,
        biosPasswordUnknownEndpoints: 0,
        dellBiosUnknownEndpoints: 0,
        metricWarningEndpoints: 0
    });

    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadStats();
        const interval = setInterval(loadStats, 30000);
        return () => clearInterval(interval);
    }, []);

    const loadStats = async () => {
        try {
            const raw = await dashboardService.getStats();
            const data = raw?.stats ? raw.stats : raw || {};

            setStats({
                totalScans: data.totalScans ?? 0,
                healthyEndpoints: data.healthyEndpoints ?? 0,
                criticalAlerts: data.criticalAlerts ?? 0,
                uniqueEndpoints: data.uniqueEndpoints ?? 0,
                completedScans: data.completedScans ?? 0,
                failedScans: data.failedScans ?? 0,
                inProgressScans: data.inProgressScans ?? 0,
                averageScanTime: data.averageScanTime ?? null,
                lastScan: data.lastScan ?? null,
                excellentCount: data.excellentCount ?? 0,
                goodCount: data.goodCount ?? 0,
                fairCount: data.fairCount ?? 0,
                poorCount: data.poorCount ?? 0,
                totalComputers: data.totalComputers ?? 0,
                activeComputers: data.activeComputers ?? 0,
                compliantEndpoints: data.compliantEndpoints ?? 0,
                partialCompliantEndpoints: data.partialCompliantEndpoints ?? 0,
                collectionFailedEndpoints: data.collectionFailedEndpoints ?? 0,
                biosPasswordUnknownEndpoints: data.biosPasswordUnknownEndpoints ?? data.dellBiosUnknownEndpoints ?? 0,
                dellBiosUnknownEndpoints: data.dellBiosUnknownEndpoints ?? 0,
                metricWarningEndpoints: data.metricWarningEndpoints ?? 0
            });
        } catch (error) {
            console.error('Failed to load stats:', error);
        } finally {
            setLoading(false);
        }
    };

    if (loading) {
        return <div className="spinner"></div>;
    }

    const totalHealth =
        (stats.excellentCount || 0) +
        (stats.goodCount || 0) +
        (stats.fairCount || 0) +
        (stats.poorCount || 0);

    const getWidth = (value) => {
        if (!totalHealth) return 0;
        return `${(value / totalHealth) * 100}%`;
    };

    const clickableCardStyle = {
        border: 'none',
        textAlign: 'left',
        width: '100%',
        cursor: 'pointer'
    };

    return (
        <div>
            <h1 style={{ marginBottom: '30px' }}>Dashboard</h1>

            <h3 style={{ marginBottom: '15px' }}>Compliance Classification</h3>

            <div className="stat-cards">
                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #2e7d32, #66bb6a)'
                    }}
                    onClick={() => navigate('/results?view=compliant')}
                    title="Open compliant endpoints"
                >
                    <div className="stat-label">COMPLIANT ENDPOINTS</div>
                    <div className="stat-value">{stats.compliantEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px' }}>
                        All required compliance fields valid
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #f57c00, #ffb74d)'
                    }}
                    onClick={() => navigate('/results?view=partial')}
                    title="Open partial compliant endpoints"
                >
                    <div className="stat-label">PARTIAL COMPLIANT</div>
                    <div className="stat-value">{stats.partialCompliantEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px' }}>
                        One or more required fields missing or unknown
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #d32f2f, #ef5350)'
                    }}
                    onClick={() => navigate('/results?view=partial&issue=collectionFailed')}
                    title="Open collection failed endpoints"
                >
                    <div className="stat-label">COLLECTION FAILED</div>
                    <div className="stat-value">{stats.collectionFailedEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px' }}>
                        Inventory collection failed / RPC unavailable
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #5e35b1, #7e57c2)'
                    }}
                    onClick={() => navigate('/results?view=partial&issue=biosPasswordUnknown')}
                    title="Open BIOS password unknown endpoints"
                >
                    <div className="stat-label">BIOS PASSWORD UNKNOWN</div>
                    <div className="stat-value">{stats.biosPasswordUnknownEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px' }}>
                        Power-on/Admin BIOS password status is unknown or not verified
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #1976d2, #64b5f6)'
                    }}
                    onClick={() => navigate('/results?view=partial&issue=metricWarning')}
                    title="Open metric warning endpoints"
                >
                    <div className="stat-label">METRIC WARNING</div>
                    <div className="stat-value">{stats.metricWarningEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px' }}>
                        Inventory completed but metric collection failed
                    </div>
                </button>
            </div>

            <div className="card">
                <h3 style={{ marginBottom: '20px' }}>System Health Overview</h3>
                <div
                    style={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
                        gap: '20px'
                    }}
                >
                    <div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                            <span>Excellent</span>
                            <strong style={{ color: 'var(--success-color)' }}>
                                {stats.excellentCount || 0}
                            </strong>
                        </div>
                        <div className="health-score-bar">
                            <div
                                className="health-score-fill health-excellent"
                                style={{ width: getWidth(stats.excellentCount || 0) }}
                            ></div>
                        </div>
                    </div>

                    <div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                            <span>Good</span>
                            <strong style={{ color: 'var(--info-color)' }}>
                                {stats.goodCount || 0}
                            </strong>
                        </div>
                        <div className="health-score-bar">
                            <div
                                className="health-score-fill health-good"
                                style={{ width: getWidth(stats.goodCount || 0) }}
                            ></div>
                        </div>
                    </div>

                    <div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                            <span>Fair</span>
                            <strong style={{ color: 'var(--warning-color)' }}>
                                {stats.fairCount || 0}
                            </strong>
                        </div>
                        <div className="health-score-bar">
                            <div
                                className="health-score-fill health-fair"
                                style={{ width: getWidth(stats.fairCount || 0) }}
                            ></div>
                        </div>
                    </div>

                    <div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                            <span>Poor</span>
                            <strong style={{ color: 'var(--error-color)' }}>
                                {stats.poorCount || 0}
                            </strong>
                        </div>
                        <div className="health-score-bar">
                            <div
                                className="health-score-fill health-poor"
                                style={{ width: getWidth(stats.poorCount || 0) }}
                            ></div>
                        </div>
                    </div>
                </div>
            </div>

            <div
                style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr 1fr',
                    gap: '20px',
                    marginTop: '20px'
                }}
            >
                <div className="card">
                    <h3 style={{ marginBottom: '15px' }}>Scan Status</h3>

                    <div
                        style={{
                            display: 'flex',
                            justifyContent: 'space-between',
                            padding: '10px 0',
                            borderBottom: '1px solid var(--border-color)'
                        }}
                    >
                        <span>Completed</span>
                        <span className="badge badge-success">{stats.completedScans || 0}</span>
                    </div>

                    <div
                        style={{
                            display: 'flex',
                            justifyContent: 'space-between',
                            padding: '10px 0',
                            borderBottom: '1px solid var(--border-color)'
                        }}
                    >
                        <span>Failed</span>
                        <span className="badge badge-danger">{stats.failedScans || 0}</span>
                    </div>

                    <div
                        style={{
                            display: 'flex',
                            justifyContent: 'space-between',
                            padding: '10px 0'
                        }}
                    >
                        <span>In Progress</span>
                        <span className="badge badge-info">{stats.inProgressScans || 0}</span>
                    </div>
                </div>

                <div className="card">
                    <h3 style={{ marginBottom: '15px' }}>Performance Metrics</h3>

                    <div
                        style={{
                            padding: '10px 0',
                            borderBottom: '1px solid var(--border-color)'
                        }}
                    >
                        <div
                            style={{
                                color: 'var(--text-secondary)',
                                fontSize: '0.9rem',
                                marginBottom: '5px'
                            }}
                        >
                            Average Scan Time
                        </div>
                        <div
                            style={{
                                fontSize: '1.5rem',
                                fontWeight: '600',
                                color: 'var(--primary-color)'
                            }}
                        >
                            {stats.averageScanTime !== null
                                ? `${Number(stats.averageScanTime).toFixed(2)}s`
                                : 'N/A'}
                        </div>
                    </div>

                    <div style={{ padding: '10px 0', marginTop: '10px' }}>
                        <div
                            style={{
                                color: 'var(--text-secondary)',
                                fontSize: '0.9rem',
                                marginBottom: '5px'
                            }}
                        >
                            Last Scan
                        </div>
                        <div style={{ fontSize: '1rem', color: 'var(--text-primary)' }}>
                            {stats.lastScan ? new Date(stats.lastScan).toLocaleString() : 'N/A'}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}

export default Dashboard;

