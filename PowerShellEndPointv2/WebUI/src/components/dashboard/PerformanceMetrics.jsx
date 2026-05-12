import React from 'react';

const PerformanceMetrics = ({ stats }) => {
    return (
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
    );
};

export default PerformanceMetrics;
