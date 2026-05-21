import React, { useState, useEffect, useCallback } from 'react';
import { adminService, errorLogService } from '../services/api';

import InfoIcon from './system-errors/InfoIcon';
import ErrorDetailModal from './system-errors/ErrorDetailModal';
import ErrorList from './system-errors/ErrorList';

import { formatTime } from "./system-errors/utils";

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

    const filtered = errors.filter(e =>
        [e.error_message, e.path, e.username].some(v =>
            (v || '').toLowerCase().includes(search.toLowerCase())
        )
    );

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

            {/* Header */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
                <div>
                    <h1 style={{ margin: 0, fontSize: '1.6rem', fontWeight: 700, color: '#0f172a' }}>
                        🐛 System Errors
                        <InfoIcon text="Centralized view of all API failures, database errors, and frontend exceptions." />
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

            <ErrorList
                search={search}
                setSearch={setSearch}
                loading={loading}
                filtered={filtered}
                setSelected={setSelected}
            />

            <ErrorDetailModal
                selected={selected}
                setSelected={setSelected}
            />
        </div>
    );
}

export default SystemErrors;
