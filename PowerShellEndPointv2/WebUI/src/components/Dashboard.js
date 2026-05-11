import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { dashboardService } from '../services/api';
import { motion } from 'framer-motion';

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

    const [range, setRange] = useState('all');
    const [loading, setLoading] = useState(true);

    const loadStats = useCallback(async () => {
        try {
            const raw = await dashboardService.getStats(range);
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
    }, [range]);

    useEffect(() => {
        loadStats();
        const interval = setInterval(loadStats, 30000);
        return () => clearInterval(interval);
    }, [loadStats]);

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

    const InfoIcon = ({ text }) => (
        <span className="tooltip-container" style={{ marginLeft: '6px', cursor: 'help', verticalAlign: 'middle', display: 'inline-flex' }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.7 }}>
                <circle cx="12" cy="12" r="10"></circle>
                <line x1="12" y1="16" x2="12" y2="12"></line>
                <line x1="12" y1="8" x2="12.01" y2="8"></line>
            </svg>
            <span className="tooltip-text">{text}</span>
        </span>
    );

    return (
        <div className="dashboard-container">
            <style>{`
                .tooltip-container { position: relative; display: inline-block; }
                .tooltip-text {
                    visibility: hidden; width: 220px; background-color: #1e293b; color: #fff;
                    text-align: center; border-radius: 6px; padding: 8px 12px; position: absolute;
                    z-index: 10; bottom: 125%; left: 50%; margin-left: -110px; opacity: 0;
                    transition: opacity 0.3s; font-size: 0.75rem; font-weight: 400; line-height: 1.4;
                    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); pointer-events: none;
                }
                .tooltip-container:hover .tooltip-text { visibility: visible; opacity: 1; }
                .tooltip-text::after {
                    content: ""; position: absolute; top: 100%; left: 50%; margin-left: -5px;
                    border-width: 5px; border-style: solid; border-color: #1e293b transparent transparent transparent;
                }
                .stat-card:hover { transform: translateY(-2px); transition: transform 0.2s; }
            `}</style>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '30px' }}>
                <h1 style={{ margin: 0, fontWeight: 700, color: '#0f172a' }}>Dashboard</h1>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <span style={{ fontSize: '0.875rem', fontWeight: 600, color: '#64748b' }}>Observation Window:</span>
                    <select 
                        className="form-control" 
                        value={range} 
                        onChange={(e) => setRange(e.target.value)}
                        style={{ width: '160px', marginBottom: 0 }}
                    >
                        <option value="all">All Time</option>
                        <option value="today">Today (So far)</option>
                        <option value="24h">Last 24 Hours</option>
                        <option value="7d">Last 7 Days</option>
                        <option value="30d">Last 30 Days</option>
                    </select>
                </div>
            </div>

            <h3 style={{ marginBottom: '15px', fontSize: '1.1rem', color: '#64748b' }}>
                Compliance Classification
                <InfoIcon text="Real-time breakdown of endpoint security and collection status across the enterprise." />
            </h3>

            <motion.div 
                className="stat-cards"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, staggerChildren: 0.1 }}
            >
                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #2e7d32, #66bb6a)'
                    }}
                    onClick={() => navigate('/results?view=compliant')}
                >
                    <div className="stat-label">
                        COMPLIANT ENDPOINTS
                        <InfoIcon text="Endpoints meeting 100% of defined enterprise security policies." />
                    </div>
                    <div className="stat-value">{stats.compliantEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
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
                >
                    <div className="stat-label">
                        PARTIAL COMPLIANT
                        <InfoIcon text="Missing one or more secondary security configurations or policy data." />
                    </div>
                    <div className="stat-value">{stats.partialCompliantEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
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
                >
                    <div className="stat-label">
                        COLLECTION FAILED
                        <InfoIcon text="Inventory collection was blocked by firewall, RPC failure, or system being offline." />
                    </div>
                    <div className="stat-value">{stats.collectionFailedEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
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
                >
                    <div className="stat-label">
                        BIOS PASSWORD
                        <InfoIcon text="The status of hardware-level passwords (Admin/System) cannot be verified." />
                    </div>
                    <div className="stat-value">{stats.biosPasswordUnknownEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        Power-on/Admin password status unknown
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
                >
                    <div className="stat-label">
                        METRIC WARNING
                        <InfoIcon text="System identity is confirmed, but performance/health telemetry collection failed." />
                    </div>
                    <div className="stat-value">{stats.metricWarningEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        Inventory completed but metric collection failed
                    </div>
                </button>
            </motion.div>

            <div className="card">
                <h3 style={{ marginBottom: '20px', fontSize: '1.1rem', color: '#64748b' }}>
                    System Health Overview
                    <InfoIcon text="Aggregated health score based on security compliance, uptime, and hardware alerts." />
                </h3>
                <div
                    style={{
                        display: 'grid',
                        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
                        gap: '25px'
                    }}
                >
                    <div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                            <span style={{ fontWeight: 600, color: '#475569' }}>
                                Excellent
                                <InfoIcon text="Fully healthy: 100% compliant and active telemetry." />
                            </span>
                            <strong style={{ color: '#16a34a', fontSize: '1.1rem' }}>
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
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                            <span style={{ fontWeight: 600, color: '#475569' }}>
                                Good
                                <InfoIcon text="Minor gaps: Mostly compliant with 1-2 non-critical missing data points." />
                            </span>
                            <strong style={{ color: '#2563eb', fontSize: '1.1rem' }}>
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
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                            <span style={{ fontWeight: 600, color: '#475569' }}>
                                Fair
                                <InfoIcon text="Warning: Significant policy violations or outdated inventory data." />
                            </span>
                            <strong style={{ color: '#ca8a04', fontSize: '1.1rem' }}>
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
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                            <span style={{ fontWeight: 600, color: '#475569' }}>
                                Poor
                                <InfoIcon text="Critical: Major security vulnerabilities or failed management connectivity." />
                            </span>
                            <strong style={{ color: '#dc2626', fontSize: '1.1rem' }}>
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
