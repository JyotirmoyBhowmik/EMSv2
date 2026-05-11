import React, { useState, useEffect, useCallback } from 'react';
import { adminService, errorLogService } from '../services/api';

const STATUS_COLORS = {
    Healthy:  { bg: '#f0fdf4', text: '#16a34a', dot: '#22c55e' },
    Degraded: { bg: '#fefce8', text: '#ca8a04', dot: '#eab308' },
    Down:     { bg: '#fef2f2', text: '#dc2626', dot: '#ef4444' },
    Unknown:  { bg: '#f8fafc', text: '#64748b', dot: '#94a3b8' }
};

function StatusBadge({ status }) {
    const s = STATUS_COLORS[status] || STATUS_COLORS.Unknown;
    return (
        <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '4px 12px', borderRadius: 12,
            background: s.bg, color: s.text, fontWeight: 600, fontSize: '0.8rem'
        }}>
            <span style={{
                width: 7, height: 7, borderRadius: '50%', background: s.dot,
                boxShadow: `0 0 5px ${s.dot}`
            }} />
            {status}
        </span>
    );
}

function ConnectorHealth() {
    const [connectors, setConnectors] = useState([]);
    const [loading,    setLoading]    = useState(true);
    const [error,      setError]      = useState(null);
    const [lastRefresh, setLastRefresh] = useState(null);

    const load = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            const data = await adminService.getConnectors();
            setConnectors(data);
            setLastRefresh(new Date());
        } catch (err) {
            setError(err.response?.data?.message || 'Failed to load connector health');
            await errorLogService.logFrontendError(err.message, err.stack, '/admin/health');
        } finally {
            setLoading(false);
        }
    }, []);

    const InfoIcon = ({ text }) => (
        <span className="tooltip-container" style={{ marginLeft: '6px', cursor: 'help', verticalAlign: 'middle', display: 'inline-flex' }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.6 }}>
                <circle cx="12" cy="12" r="10"></circle>
                <line x1="12" y1="16" x2="12" y2="12"></line>
                <line x1="12" y1="8" x2="12.01" y2="8"></line>
            </svg>
            <span className="tooltip-text">{text}</span>
        </span>
    );

    useEffect(() => {
        load();
        const interval = setInterval(load, 30000);
        return () => clearInterval(interval);
    }, [load]);

    const healthy = connectors.filter(c => c.status === 'Healthy').length;

    return (
        <div>
            <style>{`
                .tooltip-container { position: relative; display: inline-block; }
                .tooltip-text {
                    visibility: hidden; width: 180px; background-color: #1e293b; color: #fff;
                    text-align: center; border-radius: 6px; padding: 6px 10px; position: absolute;
                    z-index: 10; bottom: 125%; left: 50%; margin-left: -90px; opacity: 0;
                    transition: opacity 0.3s; font-size: 0.7rem; font-weight: 400; line-height: 1.3;
                    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); pointer-events: none;
                }
                .tooltip-container:hover .tooltip-text { visibility: visible; opacity: 1; }
                .tooltip-text::after {
                    content: ""; position: absolute; top: 100%; left: 50%; margin-left: -5px;
                    border-width: 5px; border-style: solid; border-color: #1e293b transparent transparent transparent;
                }
            `}</style>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
                <div>
                    <h1 style={{ margin: 0, fontSize: '1.6rem', fontWeight: 700, color: '#0f172a' }}>
                        Connector Health
                        <InfoIcon text="Real-time connectivity status of core infrastructure dependencies." />
                    </h1>
                    <p style={{ margin: '6px 0 0', color: '#64748b', fontSize: '0.9rem' }}>
                        Real-time status of integrated services
                        {lastRefresh && ` · Updated ${lastRefresh.toLocaleTimeString()}`}
                    </p>
                </div>
                <button
                    onClick={load}
                    disabled={loading}
                    style={{
                        padding: '8px 18px', background: '#2563eb', color: '#fff',
                        border: 'none', borderRadius: 8, cursor: loading ? 'not-allowed' : 'pointer',
                        fontWeight: 600, fontSize: '0.875rem', opacity: loading ? 0.7 : 1
                    }}
                >
                    {loading ? 'Refreshing…' : '⟳ Refresh'}
                </button>
            </div>

            {/* Summary cards */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, marginBottom: 24 }}>
                {[
                    { label: 'Total Connectors', value: connectors.length, color: '#2563eb', hint: "Number of external systems integrated with EMS." },
                    { label: 'Healthy',          value: healthy,           color: '#16a34a', hint: "Services responding within acceptable latency limits." },
                    { label: 'Issues',           value: connectors.length - healthy, color: connectors.length - healthy > 0 ? '#dc2626' : '#94a3b8', hint: "Services that are currently down or degraded." }
                ].map(card => (
                    <div key={card.label} style={{
                        background: '#fff', borderRadius: 12, padding: '18px 20px',
                        border: '1px solid #e2e8f0', boxShadow: '0 1px 4px rgba(0,0,0,0.04)'
                    }}>
                        <div style={{ fontSize: '0.78rem', color: '#94a3b8', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.5px', display: 'flex', alignItems: 'center' }}>
                            {card.label}
                            <InfoIcon text={card.hint} />
                        </div>
                        <div style={{ fontSize: '2rem', fontWeight: 800, color: card.color, marginTop: 4 }}>
                            {card.value}
                        </div>
                    </div>
                ))}
            </div>

            {error && (
                <div style={{
                    padding: '12px 16px', borderRadius: 8, background: '#fef2f2',
                    border: '1px solid #fecaca', color: '#991b1b', marginBottom: 16, fontSize: '0.875rem'
                }}>
                    ⚠️ {error}
                </div>
            )}

            {loading && connectors.length === 0 ? (
                <div style={{ textAlign: 'center', padding: 60, color: '#94a3b8' }}>Loading connectors…</div>
            ) : connectors.length === 0 ? (
                <div style={{ textAlign: 'center', padding: 60, color: '#94a3b8' }}>No connectors found.</div>
            ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 16 }}>
                    {connectors.map((c, i) => (
                        <div key={i} style={{
                            background: '#fff', borderRadius: 12, padding: '20px',
                            border: '1px solid #e2e8f0', boxShadow: '0 1px 4px rgba(0,0,0,0.04)'
                        }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 14 }}>
                                <div style={{ fontWeight: 700, color: '#1e293b', fontSize: '0.95rem' }}>{c.name}</div>
                                <StatusBadge status={c.status} />
                            </div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
                                <Metric label="Latency"    value={c.latency    || 'N/A'} />
                                <Metric label="Last Check" value={c.lastCheck  || 'N/A'} />
                                {c.version && <Metric label="Version" value={c.version} />}
                                {c.host    && <Metric label="Host"    value={c.host} />}
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}

function Metric({ label, value }) {
    return (
        <div style={{ background: '#f8fafc', borderRadius: 8, padding: '8px 12px' }}>
            <div style={{ fontSize: '0.7rem', color: '#94a3b8', fontWeight: 600, textTransform: 'uppercase', marginBottom: 2 }}>{label}</div>
            <div style={{ fontSize: '0.875rem', fontWeight: 600, color: '#1e293b' }}>{value}</div>
        </div>
    );
}

export default ConnectorHealth;
