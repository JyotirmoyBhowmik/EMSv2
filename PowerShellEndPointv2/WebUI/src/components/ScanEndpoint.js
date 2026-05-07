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
            const result = await scanService.scanSingle(target);
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
            const result = await scanService.scanBulk(bulkTargets);
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

    return (
        <div>
            <h1>Scan Endpoint</h1>

            <div className="card">
                <h3>Single Host Scan</h3>
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
                <h3>Bulk Host Scan</h3>
                <div className="form-group">
                    <label className="form-label">Upload TXT File</label>
                    <input
                        className="form-control"
                        type="file"
                        accept=".txt,text/plain"
                        onChange={handleFileUpload}
                    />
                    {fileName && <small>Selected file: {fileName}</small>}
                </div>

                <div className="form-group">
                    <label className="form-label">Hosts</label>
                    <textarea
                        className="form-control"
                        rows="10"
                        placeholder="Paste one hostname/IP per line, or comma/space separated."
                        value={bulkText}
                        onChange={(e) => setBulkText(e.target.value)}
                    />
                    <small>Total parsed hosts: {bulkTargets.length}</small>
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

