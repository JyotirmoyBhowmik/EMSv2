import React, { useState, useEffect, useCallback } from 'react';
import { adminService, errorLogService } from '../services/api';

function SystemErrors() {
    const [errors,   setErrors]   = useState([]);
    const [loading,  setLoading]  = useState(true);
    const [apiError, setApiError] = useState(null);
    const [selected, setSelected] = useState(null);
    const [search,   setSearch]   = useState('');

    const fetchErrors = useCallback(async () => {
        setLoading(true);
        setApiError(null);
        try {
            const data = await adminService.getSystemErrors();
            setErrors(Array.isArray(data) ? data : []);
        } catch (err) {
            setApiError(err.response?.data?.message || 'Unable to fetch system errors');
            await errorLogService.logFrontendError(err.message, err.stack, '/admin/errors');
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchErrors();
        const t = setInterval(fetchErrors, 30000);
        return () => clearInterval(t);
    }, [fetchErrors]);

    const handleExport = () => {
        const rows = [
            ['Timestamp', 'User', 'IP Address', 'Error Message'].join(','),
            ...filtered.map(e => [
                `"${e.timestamp || ''}"`,
                `"${e.username  || ''}"`,
                `"${e.ip_address || ''}"`,
                `"${(e.error_message || e.path || '').replace(/"/g, '""')}"`
            ].join(','))
        ];
        const blob = new Blob([rows.join('\n')], { type: 'text/csv' });
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href = url;
        a.download = `System_Errors_${new Date().toISOString().slice(0,10)}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };

    const filtered = errors.filter(e =>
        [e.error_message, e.path, e.username].some(v =>
            (v || '').toLowerCase().includes(search.toLowerCase())
        )
    );

    const formatTime = (ts) => {
        try { return new Date(ts).toLocaleString(); } catch { return ts || '—'; }
    };

    return (
        <div>
            {/* Header */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
                <div>
                    <h1 style={{ margin: 0, fontSize: '1.6rem', fontWeight: 700, color: '#0f172a' }}>
                        🐛 System Errors
                    </h1>
                    <p style={{ margin: '6px 0 0', color: '#64748b', fontSize: '0.9rem' }}>
                        Frontend crash logs &amp; backend exceptions · Auto-refreshes every 30 s
                    </p>
                </div>
                <div style={{ display: 'flex', gap: 10 }}>
                    <button
                        onClick={handleExport}
                        disabled={filtered.length === 0}
                        style={{
                            padding: '8px 16px', background: '#f1f5f9',
                            border: '1px solid #e2e8f0', borderRadius: 8,
                            cursor: filtered.length === 0 ? 'not-allowed' : 'pointer',
                            fontWeight: 600, fontSize: '0.875rem', color: '#475569',
                            opacity: filtered.length === 0 ? 0.5 : 1
                        }}
                    >
                        ↓ Export CSV
                    </button>
                    <button
                        onClick={fetchErrors}
                        disabled={loading}
                        style={{
                            padding: '8px 16px', background: '#2563eb', color: '#fff',
                            border: 'none', borderRadius: 8, cursor: loading ? 'not-allowed' : 'pointer',
                            fontWeight: 600, fontSize: '0.875rem', opacity: loading ? 0.7 : 1
                        }}
                    >
                        {loading ? 'Loading…' : '⟳ Refresh'}
                    </button>
                </div>
            </div>

            {apiError && (
                <div style={{
                    padding: '12px 16px', borderRadius: 8, background: '#fef2f2',
                    border: '1px solid #fecaca', color: '#991b1b', marginBottom: 16, fontSize: '0.875rem'
                }}>
                    ⚠️ {apiError} — Showing cached results.
                </div>
            )}

            {/* Search */}
            <div style={{ marginBottom: 20 }}>
                <input
                    type="text"
                    placeholder="🔍 Search by error message, path, or user…"
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                    style={{
                        width: '100%', padding: '10px 14px', border: '1px solid #e2e8f0',
                        borderRadius: 8, fontSize: '0.875rem', outline: 'none',
                        background: '#f8fafc', boxSizing: 'border-box'
                    }}
                />
            </div>

            {/* Table */}
            <div style={{
                background: '#fff', borderRadius: 12, border: '1px solid #e2e8f0',
                boxShadow: '0 1px 4px rgba(0,0,0,0.04)', overflow: 'hidden'
            }}>
                {loading && (
                    <div style={{ height: 3, background: 'linear-gradient(90deg,#2563eb,#7c3aed)', animation: 'none' }} />
                )}
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                    <thead>
                        <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
                            {['Timestamp', 'User', 'IP Address', 'Error Message', 'Details'].map(h => (
                                <th key={h} style={{
                                    padding: '12px 16px', textAlign: 'left', fontSize: '0.75rem',
                                    fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.5px'
                                }}>
                                    {h}
                                </th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {filtered.length === 0 ? (
                            <tr>
                                <td colSpan={5} style={{ textAlign: 'center', padding: 48, color: '#94a3b8' }}>
                                    {loading ? 'Loading…' : '✅ No errors found. Everything looks healthy!'}
                                </td>
                            </tr>
                        ) : (
                            filtered.map((err, i) => (
                                <tr key={err.request_id || i} style={{
                                    borderBottom: '1px solid #f1f5f9',
                                    cursor: 'pointer'
                                }}
                                    onMouseOver={e => e.currentTarget.style.background = '#fef2f2'}
                                    onMouseOut={e => e.currentTarget.style.background = 'transparent'}
                                >
                                    <td style={{ padding: '12px 16px', fontSize: '0.8rem', color: '#64748b', whiteSpace: 'nowrap' }}>
                                        {formatTime(err.timestamp)}
                                    </td>
                                    <td style={{ padding: '12px 16px' }}>
                                        <span style={{
                                            background: '#eff6ff', color: '#2563eb',
                                            padding: '3px 8px', borderRadius: 6,
                                            fontSize: '0.78rem', fontWeight: 600
                                        }}>
                                            {err.username || 'anonymous'}
                                        </span>
                                    </td>
                                    <td style={{ padding: '12px 16px', fontSize: '0.8rem', color: '#64748b' }}>
                                        {err.ip_address || '—'}
                                    </td>
                                    <td style={{ padding: '12px 16px', maxWidth: 400 }}>
                                        <div style={{
                                            fontFamily: 'monospace', fontSize: '0.78rem', color: '#dc2626',
                                            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'
                                        }}>
                                            {err.error_message || err.path || '—'}
                                        </div>
                                    </td>
                                    <td style={{ padding: '12px 16px', textAlign: 'center' }}>
                                        <button
                                            onClick={() => setSelected(err)}
                                            style={{
                                                padding: '5px 12px', background: '#eff6ff',
                                                border: '1px solid #bfdbfe', borderRadius: 6,
                                                cursor: 'pointer', fontSize: '0.78rem', color: '#2563eb', fontWeight: 600
                                            }}
                                        >
                                            View
                                        </button>
                                    </td>
                                </tr>
                            ))
                        )}
                    </tbody>
                </table>
            </div>

            {/* Detail Modal */}
            {selected && (
                <div
                    onClick={() => setSelected(null)}
                    style={{
                        position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
                        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000
                    }}
                >
                    <div
                        onClick={e => e.stopPropagation()}
                        style={{
                            background: '#fff', borderRadius: 16, width: '90%', maxWidth: 720,
                            maxHeight: '80vh', display: 'flex', flexDirection: 'column',
                            boxShadow: '0 20px 60px rgba(0,0,0,0.3)'
                        }}
                    >
                        <div style={{
                            padding: '16px 20px', borderBottom: '1px solid #e2e8f0',
                            display: 'flex', justifyContent: 'space-between', alignItems: 'center'
                        }}>
                            <div style={{ fontWeight: 700, color: '#dc2626', fontSize: '1rem' }}>
                                🐛 Error Details
                            </div>
                            <button
                                onClick={() => setSelected(null)}
                                style={{
                                    border: 'none', background: '#f1f5f9', borderRadius: 6,
                                    padding: '5px 10px', cursor: 'pointer', color: '#64748b', fontWeight: 700
                                }}
                            >
                                ✕
                            </button>
                        </div>
                        <div style={{ padding: '20px', overflowY: 'auto', flex: 1 }}>
                            <div style={{ marginBottom: 16 }}>
                                <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase', marginBottom: 4 }}>Time</div>
                                <div style={{ color: '#1e293b' }}>{formatTime(selected.timestamp)}</div>
                            </div>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 16 }}>
                                <div>
                                    <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase', marginBottom: 4 }}>User</div>
                                    <div style={{ color: '#1e293b', fontWeight: 600 }}>{selected.username || '—'}</div>
                                </div>
                                <div>
                                    <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase', marginBottom: 4 }}>IP Address</div>
                                    <div style={{ color: '#1e293b' }}>{selected.ip_address || '—'}</div>
                                </div>
                            </div>
                            <div>
                                <div style={{ fontSize: '0.75rem', color: '#94a3b8', textTransform: 'uppercase', marginBottom: 8 }}>Error / Stack Trace</div>
                                <pre style={{
                                    background: '#1e293b', color: '#f87171', padding: 16,
                                    borderRadius: 8, fontSize: '0.78rem', overflowX: 'auto',
                                    whiteSpace: 'pre-wrap', wordBreak: 'break-word', margin: 0
                                }}>
                                    {selected.error_message || selected.path || 'No details available'}
                                </pre>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

export default SystemErrors;
