import React, { useState, useEffect } from 'react';
import { apiClient } from '../services/api';

function EndpointLifecycle() {
    const [endpoints, setEndpoints] = useState([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [stateFilter, setStateFilter] = useState('all');
    const [selectedEp, setSelectedEp] = useState(null);
    const [notes, setNotes] = useState([]);
    const [tags, setTags] = useState([]);
    const [newNote, setNewNote] = useState('');
    const [newTag, setNewTag] = useState({ key: '', value: '' });

    const states = ['Discovered', 'Provisioned', 'Active', 'Maintenance', 'Decommissioned'];
    const stateColors = {
        Discovered: '#1976d2', Provisioned: '#7b1fa2', Active: '#2e7d32',
        Maintenance: '#f57c00', Decommissioned: '#d32f2f'
    };

    useEffect(() => { loadEndpoints(); }, []);

    const loadEndpoints = async () => {
        try {
            const res = await apiClient.get('/computers?limit=500');
            setEndpoints(res.data.computers || res.data || []);
        } catch (err) { console.error(err); }
        finally { setLoading(false); }
    };

    const updateState = async (computerName, newState) => {
        try {
            await apiClient.put(`/computers/${encodeURIComponent(computerName)}/lifecycle`, { state: newState });
            loadEndpoints();
        } catch (err) { alert('Failed: ' + (err.response?.data?.message || err.message)); }
    };

    const openDetails = async (ep) => {
        setSelectedEp(ep);
        try {
            const [noteRes, tagRes] = await Promise.all([
                apiClient.get(`/computers/${encodeURIComponent(ep.computer_name)}/notes`),
                apiClient.get(`/computers/${encodeURIComponent(ep.computer_name)}/tags`)
            ]);
            setNotes(noteRes.data.notes || []);
            setTags(tagRes.data.tags || []);
        } catch { setNotes([]); setTags([]); }
    };

    const addNote = async () => {
        if (!newNote.trim()) return;
        try {
            await apiClient.post(`/computers/${encodeURIComponent(selectedEp.computer_name)}/notes`, { text: newNote });
            setNewNote('');
            openDetails(selectedEp);
        } catch (err) { alert('Failed to add note'); }
    };

    const addTag = async () => {
        if (!newTag.key.trim()) return;
        try {
            await apiClient.post(`/computers/${encodeURIComponent(selectedEp.computer_name)}/tags`, newTag);
            setNewTag({ key: '', value: '' });
            openDetails(selectedEp);
        } catch (err) { alert('Failed to add tag'); }
    };

    const filtered = endpoints.filter(ep => {
        if (search && !(ep.computer_name || '').toLowerCase().includes(search.toLowerCase())) return false;
        if (stateFilter !== 'all' && ep.lifecycle_state !== stateFilter) return false;
        return true;
    });

    if (loading) return <div className="spinner"></div>;

    return (
        <div>
            <h1 style={{ marginBottom: '20px' }}>Endpoint Lifecycle</h1>

            {/* Filters */}
            <div style={{ display: 'flex', gap: '10px', marginBottom: '20px', flexWrap: 'wrap' }}>
                <input type="text" placeholder="Search endpoint..." value={search}
                    onChange={e => setSearch(e.target.value)}
                    style={{ padding: '10px 16px', border: '1px solid var(--border-color)', borderRadius: '6px', width: '250px', background: 'var(--bg-primary)', color: 'var(--text-primary)' }}
                />
                {['all', ...states].map(s => (
                    <button key={s} onClick={() => setStateFilter(s)} style={{
                        padding: '8px 14px', borderRadius: '20px', border: 'none', cursor: 'pointer',
                        background: stateFilter === s ? (stateColors[s] || 'var(--primary-color)') : 'var(--bg-tertiary)',
                        color: stateFilter === s ? '#fff' : 'var(--text-primary)', fontWeight: '600', fontSize: '0.85rem'
                    }}>{s === 'all' ? 'All' : s}</button>
                ))}
            </div>

            {/* Table */}
            <div className="card" style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                    <thead>
                        <tr style={{ borderBottom: '2px solid var(--border-color)' }}>
                            <th style={thStyle}>Computer Name</th>
                            <th style={thStyle}>Type</th>
                            <th style={thStyle}>OS</th>
                            <th style={thStyle}>Lifecycle State</th>
                            <th style={thStyle}>Last Seen</th>
                            <th style={thStyle}>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filtered.map((ep, i) => (
                            <tr key={i} style={{ borderBottom: '1px solid var(--border-color)' }}>
                                <td style={{ ...tdStyle, fontWeight: '600' }}>{ep.computer_name}</td>
                                <td style={tdStyle}>{ep.computer_type || '—'}</td>
                                <td style={tdStyle}>{ep.operating_system || '—'}</td>
                                <td style={tdStyle}>
                                    <select value={ep.lifecycle_state || 'Active'}
                                        onChange={e => updateState(ep.computer_name, e.target.value)}
                                        style={{
                                            padding: '4px 8px', borderRadius: '6px', border: '1px solid var(--border-color)',
                                            background: stateColors[ep.lifecycle_state] || '#666', color: '#fff', fontWeight: '600', cursor: 'pointer'
                                        }}>
                                        {states.map(s => <option key={s} value={s} style={{ background: '#333' }}>{s}</option>)}
                                    </select>
                                </td>
                                <td style={tdStyle}>{ep.last_seen ? new Date(ep.last_seen).toLocaleDateString() : '—'}</td>
                                <td style={tdStyle}>
                                    <button onClick={() => openDetails(ep)} style={{ padding: '5px 12px', color: '#fff', background: '#1976d2', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem', fontWeight: '600' }}>
                                        Details
                                    </button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>

            {/* Detail Panel */}
            {selectedEp && (
                <div style={{ position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 }}>
                    <div style={{ background: 'var(--bg-secondary)', borderRadius: '12px', padding: '30px', maxWidth: '600px', width: '90%', maxHeight: '80vh', overflowY: 'auto', boxShadow: '0 10px 40px rgba(0,0,0,0.3)' }}>
                        <h2 style={{ marginBottom: '20px' }}>{selectedEp.computer_name}</h2>

                        {/* Tags */}
                        <h4 style={{ marginBottom: '10px' }}>Tags</h4>
                        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px', marginBottom: '15px' }}>
                            {tags.map((t, i) => (
                                <span key={i} style={{ padding: '4px 12px', borderRadius: '12px', background: 'var(--bg-tertiary)', fontSize: '0.85rem' }}>
                                    <strong>{t.tag_key}</strong>: {t.tag_value}
                                </span>
                            ))}
                        </div>
                        <div style={{ display: 'flex', gap: '8px', marginBottom: '20px' }}>
                            <input placeholder="Key" value={newTag.key} onChange={e => setNewTag({ ...newTag, key: e.target.value })}
                                style={{ flex: 1, padding: '8px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-primary)', color: 'var(--text-primary)' }} />
                            <input placeholder="Value" value={newTag.value} onChange={e => setNewTag({ ...newTag, value: e.target.value })}
                                style={{ flex: 1, padding: '8px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-primary)', color: 'var(--text-primary)' }} />
                            <button onClick={addTag} style={{ padding: '8px 16px', background: 'var(--primary-color)', color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer' }}>Add</button>
                        </div>

                        {/* Notes */}
                        <h4 style={{ marginBottom: '10px' }}>Notes</h4>
                        {notes.map((n, i) => (
                            <div key={i} style={{ padding: '10px', marginBottom: '8px', background: 'var(--bg-tertiary)', borderRadius: '6px' }}>
                                <div>{n.note_text}</div>
                                <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', marginTop: '4px' }}>
                                    {n.created_by} • {new Date(n.created_at).toLocaleString()}
                                </div>
                            </div>
                        ))}
                        <div style={{ display: 'flex', gap: '8px', marginTop: '10px' }}>
                            <textarea placeholder="Add a note..." value={newNote} onChange={e => setNewNote(e.target.value)} rows="2"
                                style={{ flex: 1, padding: '8px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-primary)', color: 'var(--text-primary)', resize: 'vertical' }} />
                            <button onClick={addNote} style={{ padding: '8px 16px', background: 'var(--primary-color)', color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer', alignSelf: 'flex-end' }}>Add</button>
                        </div>

                        <div style={{ textAlign: 'right', marginTop: '20px' }}>
                            <button onClick={() => setSelectedEp(null)} style={{ padding: '10px 20px', background: '#555', color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer' }}>Close</button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

const thStyle = { textAlign: 'left', padding: '12px 10px', fontSize: '0.85rem', color: 'var(--text-secondary)' };
const tdStyle = { padding: '10px', fontSize: '0.9rem' };

export default EndpointLifecycle;
