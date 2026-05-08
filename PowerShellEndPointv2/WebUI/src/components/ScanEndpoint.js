import React, { useMemo, useState } from 'react';
import { scanService } from '../services/api';

const splitTargets = (text) => {
    return String(text || '')
        .split(/\r?\n|,|;|\s+/)
        .map((item) => item.trim())
        .filter(Boolean);
};

const ScanEndpoint = () => {
    const [singleTarget, setSingleTarget] = useState('');
    const [bulkText, setBulkText] = useState('');
    const [fileName, setFileName] = useState('');
    const [loading, setLoading] = useState(false);
    const [message, setMessage] = useState('');
    const [error, setError] = useState('');
    const [protocol, setProtocol] = useState(''); // Default to 'Auto'
    const [lastResponse, setLastResponse] = useState(null);

    const bulkTargets = useMemo(() => splitTargets(bulkText), [bulkText]);

    const handleSingleScan = async () => {
        const target = singleTarget.trim();
        if (!target) {
            setError('Please enter hostname or IP address to scan.');
            return;
        }

        setLoading(true);
        setError('');
        setMessage('');
        setLastResponse(null);

        try {
            const result = await scanService.scanSingle(target, protocol || null);
            setLastResponse(result);
            setMessage(`Scan submitted for ${target}.`);
        } catch (err) {
            setError(err?.response?.data?.message || err?.message || 'Failed to submit scan.');
        } finally {
            setLoading(false);
        }
    };

    const handleBulkScan = async () => {
        if (bulkTargets.length === 0) {
            setError('Please paste hosts or upload a .txt file containing hosts.');
            return;
        }

        setLoading(true);
        setError('');
        setMessage('');
        setLastResponse(null);

        try {
            const result = await scanService.scanBulk(bulkTargets, protocol || null);
            setLastResponse(result);
            setMessage(`Bulk scan submitted for ${bulkTargets.length} host(s).`);
        } catch (err) {
            setError(err?.response?.data?.message || err?.message || 'Failed to submit bulk scan.');
        } finally {
            setLoading(false);
        }
    };

    const handleFileUpload = async (event) => {
        const file = event.target.files?.[0];
        if (!file) return;

        setFileName(file.name);
        setError('');
        setMessage('');

        try {
            const text = await file.text();
            setBulkText(text);
            const count = splitTargets(text).length;
            setMessage(`Loaded ${count} host(s) from ${file.name}.`);
        } catch (err) {
            setError(err?.message || 'Failed to read uploaded file.');
        }
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

    return (
        <div>
            <style>{`
                .tooltip-container { position: relative; display: inline-block; }
                .tooltip-text {
                    visibility: hidden; width: 200px; background-color: #1e293b; color: #fff;
                    text-align: center; border-radius: 6px; padding: 8px 12px; position: absolute;
                    z-index: 10; bottom: 125%; left: 50%; margin-left: -100px; opacity: 0;
                    transition: opacity 0.3s; font-size: 0.75rem; font-weight: 400; line-height: 1.4;
                    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); pointer-events: none;
                }
                .tooltip-container:hover .tooltip-text { visibility: visible; opacity: 1; }
                .tooltip-text::after {
                    content: ""; position: absolute; top: 100%; left: 50%; margin-left: -5px;
                    border-width: 5px; border-style: solid; border-color: #1e293b transparent transparent transparent;
                }
            `}</style>

            <h1 style={{ marginBottom: '24px', fontWeight: 700, color: '#0f172a' }}>Scan Endpoint</h1>

            <div className="card" style={{ marginBottom: '20px', borderLeft: '4px solid #3b82f6' }}>
                <h3 style={{ marginBottom: '15px', color: '#1e293b' }}>
                    Protocol Selection (Force Option)
                    <InfoIcon text="Force a specific communication protocol. Use 'Auto' for default discovery logic." />
                </h3>
                <div className="form-group">
                    <label className="form-label">Connection Protocol</label>
                    <select 
                        className="form-control" 
                        value={protocol} 
                        onChange={(e) => setProtocol(e.target.value)}
                        style={{ maxWidth: '300px' }}
                    >
                        <option value="">Auto-detect (Default)</option>
                        <option value="DCOM">Force DCOM</option>
                        <option value="Wsman">Force WinRM / Wsman</option>
                    </select>
                    <small style={{ display: 'block', marginTop: '8px', color: '#64748b' }}>
                        <strong>Note:</strong> Forcing a protocol that is disabled on the target will cause the scan to fail.
                    </small>
                </div>
            </div>

            <div className="card" style={{ marginBottom: '20px' }}>
                <h3 style={{ marginBottom: '15px', color: '#1e293b' }}>
                    Single Host Scan
                    <InfoIcon text="Submit a specific computer for immediate inventory and compliance verification." />
                </h3>
                <div className="form-group">
                    <label className="form-label">Hostname / IP Address</label>
                    <input
                        className="form-control"
                        placeholder="Example: KTMMISLPJYOTIBH or 10.192.x.x"
                        value={singleTarget}
                        onChange={(e) => setSingleTarget(e.target.value)}
                    />
                </div>
                <button className="btn btn-primary" onClick={handleSingleScan} disabled={loading}>
                    {loading ? 'Submitting...' : 'Scan Single Host'}
                </button>
            </div>

            <div className="card">
                <h3 style={{ marginBottom: '15px', color: '#1e293b' }}>
                    Bulk Host Scan
                    <InfoIcon text="Process multiple endpoints simultaneously. Supports file upload or manual list entry." />
                </h3>
                <div className="form-group">
                    <label className="form-label">Upload TXT File</label>
                    <input
                        className="form-control"
                        type="file"
                        accept=".txt,text/plain"
                        onChange={handleFileUpload}
                    />
                    {fileName && <small style={{ display: 'block', marginTop: '4px', color: '#64748b' }}>Selected file: {fileName}</small>}
                </div>

                <div className="form-group">
                    <label className="form-label">Hosts</label>
                    <textarea
                        className="form-control"
                        rows="8"
                        placeholder="Paste one hostname/IP per line, or comma/space separated."
                        value={bulkText}
                        onChange={(e) => setBulkText(e.target.value)}
                    />
                    <small style={{ display: 'block', marginTop: '4px', color: '#64748b' }}>Total parsed hosts: {bulkTargets.length}</small>
                </div>

                <button className="btn btn-primary" onClick={handleBulkScan} disabled={loading || bulkTargets.length === 0}>
                    {loading ? 'Submitting...' : `Scan ${bulkTargets.length} Host(s)`}
                </button>
            </div>

            {message && (
                <div className="card" style={{ color: '#155724', background: '#d4edda' }}>
                    {message}
                </div>
            )}

            {error && (
                <div className="card" style={{ color: '#721c24', background: '#f8d7da' }}>
                    {error}
                </div>
            )}

            {lastResponse && (
                <div className="card">
                    <h3>API Response</h3>
                    <pre style={{ whiteSpace: 'pre-wrap' }}>{JSON.stringify(lastResponse, null, 2)}</pre>
                </div>
            )}
        </div>
    );
};

export default ScanEndpoint;

