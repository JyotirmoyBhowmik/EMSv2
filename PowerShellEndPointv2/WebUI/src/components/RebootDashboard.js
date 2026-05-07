import React, { useState, useEffect } from 'react';
import { apiClient } from '../services/api';

function RebootDashboard() {
    const [endpoints, setEndpoints] = useState([]);
    const [loading, setLoading] = useState(true);
    const [selected, setSelected] = useState([]);
    const [filter, setFilter] = useState('all');
    const [search, setSearch] = useState('');
    const [mailModal, setMailModal] = useState(false);
    const [mailForm, setMailForm] = useState({ message: '', dueDate: '' });
    const [sending, setSending] = useState(false);

    useEffect(() => { loadRebootData(); }, []);

    const loadRebootData = async () => {
        try {
            const res = await apiClient.get('/admin/reboot-status');
            const data = res.data.endpoints || [];
            setEndpoints(Array.isArray(data) ? data : []);
        } catch (err) {
            console.error('Failed to load reboot data:', err);
        } finally {
            setLoading(false);
        }
    };

    const filtered = endpoints.filter(ep => {
        if (filter !== 'all' && ep.uptime_status !== filter) return false;
        if (search && !ep.computer_name.toLowerCase().includes(search.toLowerCase())) return false;
        return true;
    });

    const stats = {
        total: endpoints.length,
        critical: endpoints.filter(e => e.uptime_status === 'Critical').length,
        warning: endpoints.filter(e => e.uptime_status === 'Warning').length,
        normal: endpoints.filter(e => e.uptime_status === 'Normal').length
    };

    const toggleSelect = (name) => {
        setSelected(prev => prev.includes(name) ? prev.filter(n => n !== name) : [...prev, name]);
    };

    const toggleAll = () => {
        if (selected.length === filtered.length) setSelected([]);
        else setSelected(filtered.map(e => e.computer_name));
    };

    const sendMail = async () => {
        setSending(true);
        try {
            await apiClient.post('/admin/send-reboot-mail', {
                computers: selected,
                customMessage: mailForm.message,
                dueDate: mailForm.dueDate
            });
            alert(`Reboot notifications sent to ${selected.length} endpoint(s)!`);
            setMailModal(false);
            setSelected([]);
        } catch (err) {
            alert('Failed to send: ' + (err.response?.data?.message || err.message));
        } finally {
            setSending(false);
        }
    };

    const getStatusColor = (status) => {
        switch (status) {
            case 'Critical': return '#d32f2f';
            case 'Warning': return '#f57c00';
            case 'Normal': return '#2e7d32';
            default: return '#666';
        }
    };

    const exportToCsv = () => {
        if (filtered.length === 0) return;
        const csvRows = ['Computer Name,Last Reboot,Uptime (Days),Status,Notified'];
        filtered.forEach(ep => {
            const date = ep.last_boot_time ? new Date(ep.last_boot_time).toLocaleDateString() : '—';
            csvRows.push(`${ep.computer_name},${date},${ep.uptime_days >= 0 ? ep.uptime_days : '—'},${ep.uptime_status},${ep.notified ? 'Yes' : 'No'}`);
        });
        const blob = new Blob([csvRows.join('\n')], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.setAttribute('hidden', '');
        a.setAttribute('href', url);
        a.setAttribute('download', 'Reboot_Monitoring_Export.csv');
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    };

    if (loading) return <div className="spinner"></div>;

    return (
        <div>
            <h1 style={{ marginBottom: '20px' }}>Reboot Monitoring</h1>

            {/* Summary Cards */}
            <div className="stat-cards">
                {[
                    { label: 'Total Endpoints', value: stats.total, color: '#1976d2' },
                    { label: 'Needs Reboot (>30d)', value: stats.critical, color: '#d32f2f' },
                    { label: 'Warning (14-30d)', value: stats.warning, color: '#f57c00' },
                    { label: 'Healthy (<14d)', value: stats.normal, color: '#2e7d32' }
                ].map((card, i) => (
                    <div key={i} className="stat-card" style={{ background: `linear-gradient(135deg, ${card.color}, ${card.color}99)` }}>
                        <div className="stat-label">{card.label}</div>
                        <div className="stat-value">{card.value}</div>
                    </div>
                ))}
            </div>

            {/* Toolbar */}
            <div style={{ display: 'flex', gap: '10px', marginBottom: '20px', flexWrap: 'wrap', alignItems: 'center' }}>
                <input type="text" placeholder="Search computer name..." value={search}
                    onChange={e => setSearch(e.target.value)}
                    style={{ padding: '10px 16px', border: '1px solid var(--border-color)', borderRadius: '6px', width: '250px', background: 'var(--bg-primary)', color: 'var(--text-primary)' }}
                />
                {['all', 'Critical', 'Warning', 'Normal'].map(f => (
                    <button key={f} onClick={() => setFilter(f)} style={{
                        padding: '8px 16px', borderRadius: '20px', border: 'none', cursor: 'pointer',
                        background: filter === f ? 'var(--primary-color)' : 'var(--bg-tertiary)',
                        color: filter === f ? '#fff' : 'var(--text-primary)', fontWeight: '600'
                    }}>{f === 'all' ? 'All' : f}</button>
                ))}
                
                <div style={{ marginLeft: 'auto', display: 'flex', gap: '10px' }}>
                    <button onClick={exportToCsv} disabled={filtered.length === 0} style={{
                        padding: '10px 20px', background: 'var(--bg-tertiary)',
                        color: 'var(--text-primary)', border: '1px solid var(--border-color)', borderRadius: '6px', cursor: 'pointer', fontWeight: '600'
                    }}>
                        📥 Export CSV
                    </button>
                    {selected.length > 0 && (
                        <button onClick={() => setMailModal(true)} style={{
                            padding: '10px 20px', background: 'linear-gradient(135deg, #7b1fa2, #ab47bc)',
                            color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer', fontWeight: '600'
                        }}>
                            📧 Send Reboot Mail ({selected.length})
                        </button>
                    )}
                </div>
            </div>

            {/* Data Table */}
            <div className="card" style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                    <thead>
                        <tr style={{ borderBottom: '2px solid var(--border-color)' }}>
                            <th style={thStyle}><input type="checkbox" onChange={toggleAll} checked={selected.length === filtered.length && filtered.length > 0} /></th>
                            <th style={thStyle}>Computer Name</th>
                            <th style={thStyle}>Last Reboot</th>
                            <th style={thStyle}>Uptime (Days)</th>
                            <th style={thStyle}>Status</th>
                            <th style={thStyle}>Notified</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filtered.map((ep, i) => (
                            <tr key={i} style={{ borderBottom: '1px solid var(--border-color)', background: selected.includes(ep.computer_name) ? 'rgba(25, 118, 210, 0.08)' : 'transparent' }}>
                                <td style={tdStyle}><input type="checkbox" checked={selected.includes(ep.computer_name)} onChange={() => toggleSelect(ep.computer_name)} /></td>
                                <td style={{ ...tdStyle, fontWeight: '600' }}>{ep.computer_name}</td>
                                <td style={tdStyle}>{ep.last_boot_time ? new Date(ep.last_boot_time).toLocaleDateString() : '—'}</td>
                                <td style={tdStyle}>{ep.uptime_days >= 0 ? ep.uptime_days : '—'}</td>
                                <td style={tdStyle}>
                                    <span style={{ padding: '4px 12px', borderRadius: '12px', fontSize: '0.8rem', fontWeight: '600', color: '#fff', background: getStatusColor(ep.uptime_status) }}>
                                        {ep.uptime_status}
                                    </span>
                                </td>
                                <td style={tdStyle}>{ep.notified ? '✅' : '—'}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
                {filtered.length === 0 && <p style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>No endpoints found.</p>}
            </div>

            {/* Mail Modal */}
            {mailModal && (
                <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
                    <div style={{ background: 'var(--bg-secondary)', borderRadius: '12px', padding: '30px', maxWidth: '500px', width: '90%', boxShadow: '0 10px 40px rgba(0,0,0,0.3)' }}>
                        <h2 style={{ marginBottom: '20px' }}>Send Reboot Notification</h2>
                        <p style={{ color: 'var(--text-secondary)', marginBottom: '15px' }}>
                            Sending to <strong>{selected.length}</strong> endpoint(s)
                        </p>
                        <label style={{ display: 'block', marginBottom: '5px', fontWeight: '600' }}>Due Date</label>
                        <input type="date" value={mailForm.dueDate} onChange={e => setMailForm({ ...mailForm, dueDate: e.target.value })}
                            style={{ width: '100%', padding: '10px', marginBottom: '15px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-primary)', color: 'var(--text-primary)' }}
                        />
                        <label style={{ display: 'block', marginBottom: '5px', fontWeight: '600' }}>Custom Message (optional)</label>
                        <textarea value={mailForm.message} onChange={e => setMailForm({ ...mailForm, message: e.target.value })}
                            rows="4" placeholder="Enter a custom message to include in the email..."
                            style={{ width: '100%', padding: '10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-primary)', color: 'var(--text-primary)', resize: 'vertical' }}
                        />
                        <div style={{ display: 'flex', gap: '10px', marginTop: '20px', justifyContent: 'flex-end' }}>
                            <button onClick={() => setMailModal(false)} style={{ padding: '10px 20px', border: '1px solid var(--border-color)', borderRadius: '6px', cursor: 'pointer', background: 'transparent', color: 'var(--text-primary)' }}>Cancel</button>
                            <button onClick={sendMail} disabled={sending} style={{ padding: '10px 20px', background: 'var(--primary-color)', color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer', fontWeight: '600', opacity: sending ? 0.5 : 1 }}>
                                {sending ? 'Sending...' : 'Send Notifications'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

const thStyle = { textAlign: 'left', padding: '12px 10px', fontSize: '0.85rem', color: 'var(--text-secondary)' };
const tdStyle = { padding: '10px', fontSize: '0.9rem' };

export default RebootDashboard;
