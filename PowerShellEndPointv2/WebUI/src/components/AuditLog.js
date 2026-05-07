import React, { useState, useEffect } from 'react';
import { apiClient } from '../services/api';

function AuditLog() {
    const [logs, setLogs] = useState([]);
    const [loading, setLoading] = useState(true);
    const [filters, setFilters] = useState({ type: 'all', user: '', dateFrom: '', dateTo: '' });
    const [logType, setLogType] = useState('api');

    const logTypes = [
        { key: 'api', label: 'API Requests' },
        { key: 'auth', label: 'Authentication' },
        { key: 'config', label: 'Config Changes' },
        { key: 'feature', label: 'Feature Toggles' }
    ];

    useEffect(() => { loadLogs(); }, [logType]);

    const loadLogs = async () => {
        setLoading(true);
        try {
            const res = await apiClient.get(`/admin/audit?type=${logType}&limit=200`);
            const data = res.data.logs || [];
            setLogs(Array.isArray(data) ? data : []);
        } catch (err) {
            console.error('Failed to load audit logs:', err);
        } finally {
            setLoading(false);
        }
    };

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

    return (
        <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <h1>Audit Logs</h1>
                <button onClick={exportCSV} style={{
                    padding: '8px 20px', background: 'var(--primary-color)', color: '#fff',
                    border: 'none', borderRadius: '6px', cursor: 'pointer'
                }}>Export CSV</button>
            </div>

            <div style={{ display: 'flex', gap: '10px', marginBottom: '20px', flexWrap: 'wrap' }}>
                {logTypes.map(lt => (
                    <button key={lt.key} onClick={() => setLogType(lt.key)} style={{
                        padding: '8px 16px', borderRadius: '20px', border: 'none', cursor: 'pointer',
                        background: logType === lt.key ? 'var(--primary-color)' : 'var(--bg-tertiary)',
                        color: logType === lt.key ? '#fff' : 'var(--text-primary)', fontWeight: '600'
                    }}>{lt.label}</button>
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
