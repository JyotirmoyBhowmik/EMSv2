import React, { useState, useEffect, useCallback } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { scanService } from '../services/api';

const ScanStatus = () => {
    const { scanId } = useParams();
    const navigate = useNavigate();
    const [scanInfo, setScanInfo] = useState(null);
    const [traces, setTraces] = useState([]);
    const [loading, setLoading] = useState(true);
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [error, setError] = useState(null);

    const loadData = useCallback(async () => {
        try {
            const [statusRes, traceRes] = await Promise.all([
                scanService.getScanStatus(scanId),
                scanService.getScanTrace(scanId)
            ]);
            
            setScanInfo(statusRes);
            setTraces(traceRes.traces || []);
            setError(null);
            
            if (statusRes.status === 'completed' || statusRes.status === 'failed') {
                setAutoRefresh(false);
            }
        } catch (err) {
            console.error('Failed to load scan status:', err);
            setError('Unable to fetch scan details. The ID might be invalid.');
        } finally {
            setLoading(false);
        }
    }, [scanId]);

    useEffect(() => {
        loadData();
        let interval;
        if (autoRefresh) {
            interval = setInterval(loadData, 2000);
        }
        return () => clearInterval(interval);
    }, [loadData, autoRefresh]);

    if (loading && !scanInfo) {
        return (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '60vh' }}>
                <div className="spinner" style={{ width: '40px', height: '40px', border: '4px solid #f3f3f3', borderTop: '4px solid #3b82f6', borderRadius: '50%', animation: 'spin 1s linear infinite' }}></div>
                <p style={{ marginTop: '16px', color: '#64748b', fontWeight: 500 }}>Initializing scan observer...</p>
                <style>{`@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }`}</style>
            </div>
        );
    }

    if (error) {
        return (
            <div className="card" style={{ textAlign: 'center', padding: '40px' }}>
                <div style={{ fontSize: '3rem', marginBottom: '16px' }}>⚠️</div>
                <h2 style={{ color: '#1e293b', marginBottom: '8px' }}>Scan Not Found</h2>
                <p style={{ color: '#64748b', marginBottom: '24px' }}>{error}</p>
                <Link to="/scan" className="btn btn-primary">Try Another Scan</Link>
            </div>
        );
    }

    const isWinRMDown = scanInfo?.errorMessage?.toLowerCase().includes('winrm') || 
                       traces.some(t => t.message?.toLowerCase().includes('winrm') || t.message?.toLowerCase().includes('ws-management'));

    const getStatusColor = (status) => {
        switch (status?.toLowerCase()) {
            case 'completed': return '#10b981';
            case 'failed': return '#ef4444';
            case 'running': return '#3b82f6';
            case 'queued': return '#f59e0b';
            default: return '#64748b';
        }
    };

    const statusColor = getStatusColor(scanInfo?.status);

    return (
        <div className="fade-in">
            {/* Header */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
                <div>
                    <h1 style={{ margin: 0, fontWeight: 700, color: '#0f172a' }}>Scan Status Observer</h1>
                    <p style={{ margin: '4px 0 0', color: '#64748b', fontSize: '0.9rem' }}>Real-time telemetry for scan job: <code style={{ color: '#3b82f6' }}>{scanId}</code></p>
                </div>
                <div style={{ display: 'flex', gap: '12px' }}>
                    <button onClick={loadData} className="btn btn-secondary" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <span>⟳</span> Refresh
                    </button>
                    <Link to="/scan" className="btn btn-primary">New Scan</Link>
                </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 350px', gap: '24px' }}>
                {/* Main Content */}
                <div>
                    {/* Status Card */}
                    <div className="card" style={{ marginBottom: '24px', position: 'relative', overflow: 'hidden' }}>
                        <div style={{ position: 'absolute', top: 0, left: 0, width: '4px', height: '100%', background: statusColor }}></div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                            <div>
                                <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: '4px' }}>Target Endpoint</label>
                                <div style={{ fontSize: '1.5rem', fontWeight: 700, color: '#1e293b' }}>{scanInfo?.target}</div>
                            </div>
                            <div style={{ textAlign: 'right' }}>
                                <div style={{ 
                                    display: 'inline-block',
                                    padding: '6px 16px',
                                    borderRadius: '9999px',
                                    background: statusColor + '15',
                                    color: statusColor,
                                    fontWeight: 700,
                                    fontSize: '0.875rem',
                                    textTransform: 'uppercase',
                                    border: `1px solid ${statusColor}30`
                                }}>
                                    {scanInfo?.status}
                                </div>
                                <div style={{ marginTop: '8px', fontSize: '0.8rem', color: '#64748b' }}>
                                    Last Updated: {new Date().toLocaleTimeString()}
                                </div>
                            </div>
                        </div>

                        {scanInfo?.status === 'running' && (
                            <div style={{ marginTop: '24px' }}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', fontSize: '0.875rem' }}>
                                    <span>Processing metrics...</span>
                                    <span>{Math.min(traces.length * 10, 95)}%</span>
                                </div>
                                <div style={{ height: '8px', background: '#f1f5f9', borderRadius: '4px', overflow: 'hidden' }}>
                                    <div style={{ 
                                        width: `${Math.min(traces.length * 10, 95)}%`, 
                                        height: '100%', 
                                        background: 'linear-gradient(90deg, #3b82f6, #60a5fa)',
                                        transition: 'width 0.5s ease'
                                    }}></div>
                                </div>
                            </div>
                        )}
                    </div>

                    {/* Trace Logs */}
                    <div className="card" style={{ padding: 0 }}>
                        <div style={{ padding: '16px 20px', borderBottom: '1px solid #e2e8f0', background: '#f8fafc', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                            <h3 style={{ margin: 0, fontSize: '1rem', fontWeight: 600 }}>Execution Trace</h3>
                            <div style={{ fontSize: '0.8rem', color: '#64748b' }}>{traces.length} steps recorded</div>
                        </div>
                        <div style={{ maxHeight: '500px', overflowY: 'auto', padding: '10px 0' }}>
                            {traces.length === 0 ? (
                                <div style={{ padding: '40px', textAlign: 'center', color: '#94a3b8' }}>
                                    Waiting for trace events...
                                </div>
                            ) : (
                                traces.map((trace, idx) => (
                                    <div key={idx} style={{ 
                                        padding: '12px 20px', 
                                        borderBottom: idx === traces.length - 1 ? 'none' : '1px solid #f1f5f9',
                                        display: 'flex',
                                        gap: '16px'
                                    }}>
                                        <div style={{ width: '80px', flexShrink: 0, fontSize: '0.75rem', color: '#94a3b8', paddingTop: '2px' }}>
                                            {new Date(trace.timestamp).toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                                        </div>
                                        <div style={{ flex: 1 }}>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '2px' }}>
                                                <span style={{ fontWeight: 600, fontSize: '0.9rem', color: '#334155' }}>{trace.step_name}</span>
                                                <span style={{ 
                                                    fontSize: '0.7rem', 
                                                    padding: '2px 6px', 
                                                    borderRadius: '4px', 
                                                    background: trace.status === 'Error' ? '#fef2f2' : (trace.status === 'Success' ? '#f0fdf4' : '#eff6ff'),
                                                    color: trace.status === 'Error' ? '#ef4444' : (trace.status === 'Success' ? '#10b981' : '#3b82f6'),
                                                    fontWeight: 600
                                                }}>{trace.status}</span>
                                            </div>
                                            <div style={{ fontSize: '0.85rem', color: '#64748b' }}>{trace.message}</div>
                                        </div>
                                    </div>
                                ))
                            )}
                        </div>
                    </div>
                </div>

                {/* Sidebar Diagnostics */}
                <div>
                    {isWinRMDown && (
                        <div className="card" style={{ background: '#fff1f2', border: '1px solid #fecdd3', color: '#9f1239', marginBottom: '20px' }}>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                                <span style={{ fontSize: '1.5rem' }}>🛑</span>
                                <h3 style={{ margin: 0, fontSize: '1.1rem', fontWeight: 700 }}>WinRM is Down</h3>
                            </div>
                            <p style={{ fontSize: '0.875rem', marginBottom: '16px', lineHeight: 1.5 }}>
                                The target endpoint is not responding to WS-Management requests. This usually means the WinRM service is stopped or the firewall is blocking port 5985/5986.
                            </p>
                            <div style={{ background: 'rgba(255,255,255,0.5)', padding: '12px', borderRadius: '8px' }}>
                                <h4 style={{ margin: '0 0 8px 0', fontSize: '0.8rem', textTransform: 'uppercase' }}>Quick Fix (Run as Admin):</h4>
                                <pre style={{ 
                                    margin: 0, 
                                    fontSize: '0.75rem', 
                                    background: '#1e293b', 
                                    color: '#f8fafc', 
                                    padding: '10px', 
                                    borderRadius: '4px',
                                    whiteSpace: 'pre-wrap'
                                }}>
                                    winrm quickconfig -q{"\n"}
                                    Enable-PSRemoting -Force
                                </pre>
                            </div>
                            <button 
                                onClick={() => navigate('/scan')}
                                style={{ 
                                    marginTop: '16px', 
                                    width: '100%', 
                                    padding: '10px', 
                                    background: '#9f1239', 
                                    color: 'white', 
                                    border: 'none', 
                                    borderRadius: '6px',
                                    fontWeight: 600,
                                    cursor: 'pointer'
                                }}
                            >
                                Try Again After Fix
                            </button>
                        </div>
                    )}

                    <div className="card" style={{ background: '#f8fafc' }}>
                        <h3 style={{ margin: '0 0 16px 0', fontSize: '1rem', fontWeight: 600 }}>Scan Details</h3>
                        <div style={{ display: 'grid', gap: '12px' }}>
                            <div>
                                <label style={{ display: 'block', fontSize: '0.7rem', color: '#64748b', textTransform: 'uppercase' }}>Started At</label>
                                <div style={{ fontSize: '0.875rem' }}>{scanInfo?.startedAt ? new Date(scanInfo.startedAt).toLocaleString() : '—'}</div>
                            </div>
                            <div>
                                <label style={{ display: 'block', fontSize: '0.7rem', color: '#64748b', textTransform: 'uppercase' }}>Execution Time</label>
                                <div style={{ fontSize: '0.875rem' }}>{scanInfo?.executionTimeSeconds ? `${scanInfo.executionTimeSeconds}s` : 'Calculating...'}</div>
                            </div>
                            {scanInfo?.status === 'completed' && (
                                <Link to={`/results`} className="btn btn-primary" style={{ textAlign: 'center', marginTop: '10px' }}>
                                    View Metric Report
                                </Link>
                            )}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default ScanStatus;
