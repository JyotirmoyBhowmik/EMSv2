import React, { useState, useEffect, useCallback } from 'react';
import { adminService } from '../services/api';

function AuditLog() {
    const [logs, setLogs] = useState([]);
    const [loading, setLoading] = useState(true);
    const [filters, setFilters] = useState({ user: '', dateFrom: '', dateTo: '', statusFilter: 'all' });
    const [logType, setLogType] = useState('api');
    const [page, setPage] = useState(1);
    const pageSize = 50;

    const logTypes = [
        { key: 'api',     label: 'API Requests'    },
        { key: 'auth',    label: 'Authentication'   },
        { key: 'config',  label: 'Config Changes'   },
        { key: 'feature', label: 'Feature Toggles'  }
    ];

    const loadLogs = useCallback(async () => {
        setLoading(true);
        try {
            const params = { type: logType, limit: 500 };
            const data = await adminService.getAuditLogs(params);
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
        if (filters.user && !(log.username || log.changed_by || '').toLowerCase().includes(filters.user.toLowerCase())) return false;
        if (filters.dateFrom) {
            const logDate = new Date(log.timestamp).toISOString().split('T')[0];
            if (logDate < filters.dateFrom) return false;
        }
        if (filters.dateTo) {
            const logDate = new Date(log.timestamp).toISOString().split('T')[0];
            if (logDate > filters.dateTo) return false;
        }
        if (filters.statusFilter !== 'all' && logType === 'api') {
            const code = log.status_code || 0;
            if (filters.statusFilter === 'success' && code >= 400) return false;
            if (filters.statusFilter === 'error' && code < 400) return false;
        }
        return true;
    });

    const totalPages = Math.ceil(filteredLogs.length / pageSize);
    const paginatedLogs = filteredLogs.slice((page - 1) * pageSize, page * pageSize);

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

            <div style={{ marginBottom: 16, padding: 16, background: '#fff', borderRadius: 10, border: '1px solid #e2e8f0', display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'flex-end' }}>
                <div>
                    <label style={filterLabel}>Username</label>
                    <input type="text" placeholder="Filter by user..." value={filters.user}
                        onChange={e => { setFilters({ ...filters, user: e.target.value }); setPage(1); }}
                        style={filterInput} />
                </div>
                <div>
                    <label style={filterLabel}>From Date</label>
                    <input type="date" value={filters.dateFrom}
                        onChange={e => { setFilters({ ...filters, dateFrom: e.target.value }); setPage(1); }}
                        style={filterInput} />
                </div>
                <div>
                    <label style={filterLabel}>To Date</label>
                    <input type="date" value={filters.dateTo}
                        onChange={e => { setFilters({ ...filters, dateTo: e.target.value }); setPage(1); }}
                        style={filterInput} />
                </div>
                {logType === 'api' && (
                    <div>
                        <label style={filterLabel}>Status</label>
                        <select value={filters.statusFilter}
                            onChange={e => { setFilters({ ...filters, statusFilter: e.target.value }); setPage(1); }}
                            style={filterInput}>
                            <option value="all">All</option>
                            <option value="success">Success (2xx/3xx)</option>
                            <option value="error">Errors (4xx/5xx)</option>
                        </select>
                    </div>
                )}
                <div style={{ marginLeft: 'auto', fontSize: '0.85rem', color: '#64748b', alignSelf: 'center' }}>
                    {filteredLogs.length} records · Page {page}/{totalPages || 1}
                </div>
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
                            {paginatedLogs.map((log, i) => (
                                <tr key={i} style={{ borderBottom: '1px solid var(--border-color)' }}>
                                    <td style={tdStyle}>{new Date(log.timestamp).toLocaleString()}</td>
                                    <td style={tdStyle}>{log.username || log.changed_by || '—'}</td>
                                    {logType === 'api' && <>
                                        <td style={tdStyle}><span style={{ padding: '2px 8px', borderRadius: 4, fontSize: '0.75rem', fontWeight: 600, background: log.method === 'GET' ? '#eff6ff' : log.method === 'POST' ? '#f0fdf4' : '#fff7ed', color: log.method === 'GET' ? '#2563eb' : log.method === 'POST' ? '#16a34a' : '#ea580c' }}>{log.method}</span></td>
                                        <td style={tdStyle}><code style={{ fontSize: '0.8rem' }}>{log.path}</code></td>
                                        <td style={tdStyle}><span style={{ padding: '2px 8px', borderRadius: 4, fontSize: '0.75rem', fontWeight: 600, background: (log.status_code || 0) < 400 ? '#f0fdf4' : '#fef2f2', color: (log.status_code || 0) < 400 ? '#16a34a' : '#dc2626' }}>{log.status_code}</span></td>
                                        <td style={tdStyle}>{log.response_time_ms != null ? `${Math.round(log.response_time_ms)}ms` : '—'}</td>
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
                    {paginatedLogs.length === 0 && (
                        <p style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>No audit records found.</p>
                    )}
                </div>
            )}

            {/* Pagination */}
            {totalPages > 1 && (
                <div style={{ display: 'flex', justifyContent: 'center', gap: 6, marginTop: 16 }}>
                    <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1}
                        style={{ ...paginationBtn, opacity: page === 1 ? 0.4 : 1 }}>← Prev</button>
                    {Array.from({ length: Math.min(totalPages, 7) }, (_, i) => {
                        let pn;
                        if (totalPages <= 7) pn = i + 1;
                        else if (page <= 4) pn = i + 1;
                        else if (page >= totalPages - 3) pn = totalPages - 6 + i;
                        else pn = page - 3 + i;
                        return (
                            <button key={pn} onClick={() => setPage(pn)}
                                style={{ ...paginationBtn, background: page === pn ? '#2563eb' : '#f1f5f9', color: page === pn ? '#fff' : '#64748b' }}>{pn}</button>
                        );
                    })}
                    <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages}
                        style={{ ...paginationBtn, opacity: page === totalPages ? 0.4 : 1 }}>Next →</button>
                </div>
            )}
        </div>
    );
}

const thStyle = { textAlign: 'left', padding: '12px 10px', fontSize: '0.85rem', color: 'var(--text-secondary)' };
const tdStyle = { padding: '10px', fontSize: '0.9rem' };
const filterLabel = { display: 'block', fontSize: '0.7rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: 4 };
const filterInput = { padding: '8px 12px', border: '1px solid #e2e8f0', borderRadius: 6, fontSize: '0.85rem', background: '#fff', minWidth: 140 };
const paginationBtn = { padding: '6px 14px', border: '1px solid #e2e8f0', borderRadius: 6, fontSize: '0.8rem', fontWeight: 600, cursor: 'pointer', background: '#f1f5f9', color: '#64748b' };

export default AuditLog;
