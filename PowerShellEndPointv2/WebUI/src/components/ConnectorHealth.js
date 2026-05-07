import React, { useState, useEffect } from 'react';
import { apiClient } from '../services/api';

function ConnectorHealth() {
    const [connectors, setConnectors] = useState([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadHealth();
        const interval = setInterval(loadHealth, 60000);
        return () => clearInterval(interval);
    }, []);

    const loadHealth = async () => {
        try {
            const res = await apiClient.get('/admin/connectors');
            setConnectors(res.data.connectors || []);
        } catch (err) {
            console.error('Failed to load connector health:', err);
        } finally {
            setLoading(false);
        }
    };

    const getStatusIcon = (status) => {
        switch (status) {
            case 'Healthy': return '🟢';
            case 'Down': return '🔴';
            case 'Not Configured': return '⚪';
            default: return '🟡';
        }
    };

    const getStatusBg = (status) => {
        switch (status) {
            case 'Healthy': return 'linear-gradient(135deg, #1b5e20, #2e7d32)';
            case 'Down': return 'linear-gradient(135deg, #b71c1c, #d32f2f)';
            default: return 'linear-gradient(135deg, #424242, #616161)';
        }
    };

    if (loading) return <div className="spinner"></div>;

    return (
        <div>
            <h1 style={{ marginBottom: '10px' }}>Connector Health</h1>
            <p style={{ color: 'var(--text-secondary)', marginBottom: '30px' }}>
                Real-time health status of all system connectors. Auto-refreshes every 60 seconds.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '20px' }}>
                {connectors.map((conn, i) => (
                    <div key={i} style={{
                        background: getStatusBg(conn.status), borderRadius: '12px',
                        padding: '24px', color: '#fff', position: 'relative', overflow: 'hidden'
                    }}>
                        <div style={{ fontSize: '2rem', marginBottom: '10px' }}>
                            {getStatusIcon(conn.status)}
                        </div>
                        <div style={{ fontSize: '1.2rem', fontWeight: '700', marginBottom: '6px' }}>
                            {conn.connector}
                        </div>
                        <div style={{
                            fontSize: '0.9rem', opacity: 0.9, marginBottom: '12px',
                            display: 'flex', alignItems: 'center', gap: '8px'
                        }}>
                            <span style={{
                                padding: '2px 10px', borderRadius: '10px', fontSize: '0.8rem',
                                fontWeight: '600', background: 'rgba(255,255,255,0.2)'
                            }}>{conn.status}</span>
                            {conn.latency && <span>• {conn.latency}</span>}
                        </div>
                        <div style={{ fontSize: '0.85rem', opacity: 0.8, lineHeight: '1.4' }}>
                            {conn.message}
                        </div>
                        <div style={{ fontSize: '0.75rem', opacity: 0.6, marginTop: '12px' }}>
                            Last checked: {conn.last_check || conn.lastCheck || '—'}
                        </div>
                    </div>
                ))}
            </div>

            <div style={{ marginTop: '20px', textAlign: 'center' }}>
                <button onClick={loadHealth} style={{
                    padding: '10px 24px', background: 'var(--primary-color)', color: '#fff',
                    border: 'none', borderRadius: '6px', cursor: 'pointer', fontWeight: '600'
                }}>Refresh Now</button>
            </div>
        </div>
    );
}

export default ConnectorHealth;
