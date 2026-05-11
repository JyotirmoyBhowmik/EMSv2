import React, { useState, useEffect, useCallback } from 'react';
import { useParams, Link } from 'react-router-dom';
import { scanService } from '../services/api';

const ScanTrace = () => {
    const { scanId } = useParams();
    const [scanInfo, setScanInfo] = useState(null);
    const [traces, setTraces] = useState([]);
    const [loading, setLoading] = useState(true);
    const [autoRefresh, setAutoRefresh] = useState(true);

    const loadData = useCallback(async () => {
        try {
            const [statusRes, traceRes] = await Promise.all([
                scanService.getScanStatus(scanId),
                scanService.getScanTrace(scanId)
            ]);
            
            setScanInfo(statusRes);
            setTraces(traceRes.traces || []);
            
            if (statusRes.status === 'completed' || statusRes.status === 'failed') {
                setAutoRefresh(false);
            }
        } catch (err) {
            console.error('Failed to load trace data:', err);
        } finally {
            setLoading(false);
        }
    }, [scanId]);

    useEffect(() => {
        loadData();
        let interval;
        if (autoRefresh) {
            interval = setInterval(loadData, 3000);
        }
        return () => clearInterval(interval);
    }, [loadData, autoRefresh]);

    if (loading && !scanInfo) {
        return <div className="card">Loading trace data...</div>;
    }

    const getStatusBadge = (status) => {
        const colors = {
            queued: '#64748b',
            running: '#3b82f6',
            completed: '#10b981',
            failed: '#ef4444'
        };
        return (
            <span style={{ 
                backgroundColor: colors[status?.toLowerCase()] || '#64748b',
                color: 'white',
                padding: '4px 12px',
                borderRadius: '9999px',
                fontSize: '0.75rem',
                fontWeight: '600',
                textTransform: 'uppercase'
            }}>
                {status}
            </span>
        );
    };

    return (
        <div className="fade-in">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
                <h1 style={{ fontWeight: 700, color: '#0f172a', margin: 0 }}>Scan Observability</h1>
                <Link to="/results" className="btn btn-secondary">Back to Results</Link>
            </div>

            <div className="card" style={{ marginBottom: '24px', borderTop: '4px solid #3b82f6' }}>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '20px' }}>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase' }}>Scan ID</label>
                        <div style={{ fontWeight: 500 }}>{scanId}</div>
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase' }}>Target</label>
                        <div style={{ fontWeight: 600, color: '#1e293b' }}>{scanInfo?.target}</div>
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase' }}>Current Status</label>
                        <div style={{ marginTop: '4px' }}>{getStatusBadge(scanInfo?.status)}</div>
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase' }}>Auto Refresh</label>
                        <div style={{ display: 'flex', alignItems: 'center', marginTop: '4px' }}>
                            <input 
                                type="checkbox" 
                                checked={autoRefresh} 
                                onChange={(e) => setAutoRefresh(e.target.checked)}
                                style={{ marginRight: '8px' }}
                            />
                            <span style={{ fontSize: '0.875rem' }}>{autoRefresh ? 'Active (3s)' : 'Paused'}</span>
                        </div>
                    </div>
                </div>
                {scanInfo?.errorMessage && (
                    <div style={{ marginTop: '16px', padding: '12px', background: '#fef2f2', border: '1px solid #fee2e2', borderRadius: '6px', color: '#991b1b' }}>
                        <strong>Error:</strong> {scanInfo.errorMessage}
                    </div>
                )}
            </div>

            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{ padding: '16px 24px', borderBottom: '1px solid #e2e8f0', background: '#f8fafc' }}>
                    <h3 style={{ margin: 0, fontSize: '1.1rem', color: '#1e293b' }}>Execution Trace Logs</h3>
                </div>
                <div style={{ overflowX: 'auto' }}>
                    <table className="table" style={{ margin: 0 }}>
                        <thead>
                            <tr>
                                <th style={{ width: '180px' }}>Timestamp</th>
                                <th style={{ width: '150px' }}>Step</th>
                                <th style={{ width: '150px' }}>Module</th>
                                <th style={{ width: '100px' }}>Status</th>
                                <th>Message</th>
                            </tr>
                        </thead>
                        <tbody>
                            {traces.length === 0 ? (
                                <tr>
                                    <td colSpan="5" style={{ textAlign: 'center', padding: '40px', color: '#64748b' }}>
                                        No trace logs found for this scan.
                                    </td>
                                </tr>
                            ) : (
                                traces.map((trace) => (
                                    <tr key={trace.trace_id}>
                                        <td style={{ fontSize: '0.8rem', color: '#64748b' }}>
                                            {new Date(trace.timestamp).toLocaleString()}
                                        </td>
                                        <td style={{ fontWeight: 600, color: '#334155' }}>{trace.step_name}</td>
                                        <td>
                                            <code style={{ fontSize: '0.75rem', background: '#f1f5f9', padding: '2px 6px', borderRadius: '4px' }}>
                                                {trace.module_name}
                                            </code>
                                        </td>
                                        <td>
                                            <span style={{ 
                                                color: trace.status === 'Error' ? '#ef4444' : (trace.status === 'Success' ? '#10b981' : '#3b82f6'),
                                                fontWeight: 600,
                                                fontSize: '0.8rem'
                                            }}>
                                                {trace.status}
                                            </span>
                                        </td>
                                        <td style={{ fontSize: '0.875rem', color: '#1e293b' }}>{trace.message}</td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    );
};

export default ScanTrace;
