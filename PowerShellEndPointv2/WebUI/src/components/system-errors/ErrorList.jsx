import { formatTime } from "./utils";
import React from 'react';


const ErrorList = ({ search, setSearch, loading, filtered, setSelected }) => {
    return (
        <>
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
        </>
    );
};

export default ErrorList;
