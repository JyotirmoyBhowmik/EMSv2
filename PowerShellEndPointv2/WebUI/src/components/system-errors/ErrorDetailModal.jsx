import { formatTime } from "./utils";
import React from 'react';


const ErrorDetailModal = ({ selected, setSelected }) => {
    if (!selected) return null;

    return (
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
                        aria-label="Close error details"
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
    );
};

export default ErrorDetailModal;
