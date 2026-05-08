import React, { useState, useEffect, useCallback } from 'react';
import { adminService } from '../services/api';

function AuditLog() {
    const [logs, setLogs] = useState([]);
    const [loading, setLoading] = useState(true);
    const [filters, setFilters] = useState({ type: 'all', user: '', dateFrom: '', dateTo: '' });
    const [logType, setLogType] = useState('api');

    const logTypes = [
        { key: 'api',     label: 'API Requests'    },
        { key: 'auth',    label: 'Authentication'   },
        { key: 'config',  label: 'Config Changes'   },
        { key: 'feature', label: 'Feature Toggles'  }
    ];

    const loadLogs = useCallback(async () => {
        setLoading(true);
        try {
            const data = await adminService.getAuditLogs(logType, 200);
            setLogs(Array.isArray(data) ? data : []);
        } catch (err) {
            console.error('Failed to load audit logs:', err);
            setLogs([]);
        } finally {
            setLoading(false);
        }
    }, [logType]);

    useEffect(() => { loadLogs(); }, [loadLogs]);

    const filteredLogs = logs.filter(log => {
        if (filters.user && !(log.username || '').toLowerCase().includes(filters.user.toLowerCase())) return false;
        return true;
    });

    const getRiskColor = (risk) => {
        switch (risk) {
            case 'Critical': return '#d32f2f';
            case 'High': return '#f57c00';
            case 'Medium': return '#fbc02d';
            default: return '#66bb6a';
        }
    };

    const exportCSV = () => {
        const headers = Object.keys(filteredLogs[0] || {}).join(',');
        const rows = filteredLogs.map(log => Object.values(log).map(v => `"${v || ''}"`).join(','));
        const csv = [headers, ...rows].join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url; a.download = `audit_${logType}_${new Date().toISOString().split('T')[0]}.csv`;
        a.click();
    };

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

    const logTypeHints = {
        api: "Records of every HTTP request made to the EMS API server.",
        auth: "Login attempts, token renewals, and security-related events.",
        config: "System-wide configuration changes and database updates.",
        feature: "Manual toggling of enterprise features by administrators."
    };

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

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <h1 style={{ margin: 0, fontSize: '1.6rem', fontWeight: 700, color: '#0f172a' }}>
                    Audit Logs
                    <InfoIcon text="Tamper-proof record of all system activities and administrative changes." />
                </h1>
                <button onClick={exportCSV} style={{
                    padding: '8px 20px', background: '#2563eb', color: '#fff',
                    border: 'none', borderRadius: '6px', cursor: 'pointer', fontWeight: 600
                }}>Export CSV</button>
            </div>

            <div style={{ display: 'flex', gap: '10px', marginBottom: '20px', flexWrap: 'wrap' }}>
                {logTypes.map(lt => (
                    <button key={lt.key} onClick={() => setLogType(lt.key)} style={{
                        padding: '8px 16px', borderRadius: '20px', border: 'none', cursor: 'pointer',
                        background: logType === lt.key ? '#1e293b' : '#f1f5f9',
                        color: logType === lt.key ? '#fff' : '#64748b', fontWeight: '600',
                        display: 'flex', alignItems: 'center'
                    }}>
                        {lt.label}
                        <InfoIcon text={logTypeHints[lt.key]} />
                    </button>
                ))}
            </div>

            <div className="card" style={{ marginBottom: '20px' }}>
                <input
                    type="text" placeholder="Filter by username..." value={filters.user}
                    onChange={e => setFilters({ ...filters, user: e.target.value })}
                    style={{
                        padding: '10px 16px', border: '1px solid var(--border-color)',
                        borderRadius: '6px', width: '300px', background: 'var(--bg-primary)',
                        color: 'var(--text-primary)'
                    }}
                />
                <span style={{ marginLeft: '15px', color: 'var(--text-secondary)' }}>
                    Showing {filteredLogs.length} records
                </span>
            </div>

            {loading ? <div className="spinner"></div> : (
                <div className="card" style={{ overflowX: 'auto' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                        <thead>
                            <tr style={{ borderBottom: '2px solid var(--border-color)' }}>
                                <th style={thStyle}>Timestamp</th>
                                <th style={thStyle}>User</th>
                                {logType === 'api' && <><th style={thStyle}>Method</th><th style={thStyle}>Path</th><th style={thStyle}>Status</th><th style={thStyle}>Latency</th></>}
                                {logType === 'auth' && <><th style={thStyle}>Event</th><th style={thStyle}>Provider</th><th style={thStyle}>Risk</th></>}
                                {logType === 'config' && <><th style={thStyle}>Section</th><th style={thStyle}>Key</th><th style={thStyle}>Old → New</th></>}
                                {logType === 'feature' && <><th style={thStyle}>Feature</th><th style={thStyle}>Change</th></>}
                            </tr>
                        </thead>
                        <tbody>
                            {filteredLogs.map((log, i) => (
                                <tr key={i} style={{ borderBottom: '1px solid var(--border-color)' }}>
                                    <td style={tdStyle}>{new Date(log.timestamp).toLocaleString()}</td>
                                    <td style={tdStyle}>{log.username || log.changed_by || '—'}</td>
                                    {logType === 'api' && <>
                                        <td style={tdStyle}><span className={`badge badge-${log.method === 'GET' ? 'info' : 'warning'}`}>{log.method}</span></td>
                                        <td style={tdStyle}><code>{log.path}</code></td>
                                        <td style={tdStyle}><span className={`badge badge-${log.status_code < 400 ? 'success' : 'danger'}`}>{log.status_code}</span></td>
                                        <td style={tdStyle}>{log.response_time_ms}ms</td>
                                    </>}
                                    {logType === 'auth' && <>
                                        <td style={tdStyle}>{log.event_type}</td>
                                        <td style={tdStyle}>{log.provider || '—'}</td>
                                        <td style={tdStyle}><span style={{ color: getRiskColor(log.risk_level), fontWeight: 600 }}>{log.risk_level}</span></td>
                                    </>}
                                    {logType === 'config' && <>
                                        <td style={tdStyle}>{log.config_section}</td>
                                        <td style={tdStyle}><code>{log.config_key}</code></td>
                                        <td style={tdStyle}>{log.old_value} → {log.new_value}</td>
                                    </>}
                                    {logType === 'feature' && <>
                                        <td style={tdStyle}>{log.feature_key}</td>
                                        <td style={tdStyle}>{log.old_value ? 'ON' : 'OFF'} → {log.new_value ? 'ON' : 'OFF'}</td>
                                    </>}
                                </tr>
                            ))}
                        </tbody>
                    </table>
                    {filteredLogs.length === 0 && (
                        <p style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>No audit records found.</p>
                    )}
                </div>
            )}
        </div>
    );
}

const thStyle = { textAlign: 'left', padding: '12px 10px', fontSize: '0.85rem', color: 'var(--text-secondary)' };
const tdStyle = { padding: '10px', fontSize: '0.9rem' };

export default AuditLog;
