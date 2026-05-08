import React, { useState, useEffect } from 'react';
import { historicalService } from '../services/api';

const HistoricalReports = () => {
    const [view, setView] = useState('heatmap');
    const [data, setData] = useState([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    
    // Cutover filters
    const [beforeDate, setBeforeDate] = useState('');
    const [afterDate, setAfterDate] = useState('');

    const loadReport = async () => {
        setLoading(true);
        setError('');
        try {
            let res;
            if (view === 'heatmap') res = await historicalService.getHeatmap();
            else if (view === 'drift') res = await historicalService.getDriftAnalysis();
            else if (view === 'cutover') {
                if (!beforeDate || !afterDate) {
                    setError('Please select both Before and After dates');
                    setLoading(false);
                    return;
                }
                res = await historicalService.getCutoverReport({ before: beforeDate, after: afterDate });
            }
            setData(res.data || []);
        } catch (err) {
            setError(err.friendlyMessage || 'Failed to load report');
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        if (view !== 'cutover') loadReport();
    }, [view]);

    return (
        <div className="reports-container">
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <h1>Advanced Reporting</h1>
                <div className="btn-group">
                    <button className={`btn ${view === 'heatmap' ? 'btn-primary' : ''}`} onClick={() => setView('heatmap')}>Compliance Heatmap</button>
                    <button className={`btn ${view === 'drift' ? 'btn-primary' : ''}`} onClick={() => setView('drift')}>Drift Analysis</button>
                    <button className={`btn ${view === 'cutover' ? 'btn-primary' : ''}`} onClick={() => setView('cutover')}>Cutover Comparison</button>
                </div>
            </div>

            {view === 'cutover' && (
                <div className="card" style={{ display: 'flex', gap: '15px', alignItems: 'center', marginBottom: '20px' }}>
                    <div>
                        <label style={{ marginRight: '10px' }}>Before Date:</label>
                        <input type="date" className="form-control" value={beforeDate} onChange={(e) => setBeforeDate(e.target.value)} style={{ width: 'auto', display: 'inline-block' }} />
                    </div>
                    <div>
                        <label style={{ marginRight: '10px' }}>After Date:</label>
                        <input type="date" className="form-control" value={afterDate} onChange={(e) => setAfterDate(e.target.value)} style={{ width: 'auto', display: 'inline-block' }} />
                    </div>
                    <button className="btn btn-primary" onClick={loadReport} disabled={loading}>Generate Report</button>
                </div>
            )}

            {loading ? (
                <div className="spinner"></div>
            ) : error ? (
                <div className="alert alert-danger">{error}</div>
            ) : (
                <div className="card">
                    {data.length === 0 ? (
                        <p style={{ textAlign: 'center', padding: '20px' }}>No data found for the selected period.</p>
                    ) : (
                        <div className="table-container">
                            <table>
                                <thead>
                                    <tr>
                                        <th>Target / Endpoint</th>
                                        {view === 'heatmap' && <th>Health Score</th>}
                                        {view === 'heatmap' && <th>Last Seen</th>}
                                        {view === 'drift' && <th>Previous Score</th>}
                                        {view === 'drift' && <th>Current Score</th>}
                                        {view === 'drift' && <th>Score Drop</th>}
                                        {view === 'cutover' && <th>Score Before</th>}
                                        {view === 'cutover' && <th>Score After</th>}
                                        {view === 'cutover' && <th>Change</th>}
                                    </tr>
                                </thead>
                                <tbody>
                                    {data.map((row, idx) => (
                                        <tr key={idx}>
                                            <td>{row.short_name || row.target}</td>
                                            {view === 'heatmap' && <td>
                                                <span className={`badge ${row.health_score >= 90 ? 'badge-success' : row.health_score >= 70 ? 'badge-info' : 'badge-danger'}`}>
                                                    {row.health_score}%
                                                </span>
                                            </td>}
                                            {view === 'heatmap' && <td>{new Date(row.completed_at).toLocaleString()}</td>}
                                            {view === 'drift' && <td>{row.prev_score}%</td>}
                                            {view === 'drift' && <td>{row.current_score}%</td>}
                                            {view === 'drift' && <td style={{ color: '#dc2626', fontWeight: 'bold' }}>-{row.drop} pts</td>}
                                            {view === 'cutover' && <td>{row.score_before}%</td>}
                                            {view === 'cutover' && <td>{row.score_after}%</td>}
                                            {view === 'cutover' && <td style={{ color: row.change >= 0 ? '#16a34a' : '#dc2626', fontWeight: 'bold' }}>
                                                {row.change > 0 ? '+' : ''}{row.change} pts
                                            </td>}
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    )}
                </div>
            )}
        </div>
    );
};

export default HistoricalReports;
