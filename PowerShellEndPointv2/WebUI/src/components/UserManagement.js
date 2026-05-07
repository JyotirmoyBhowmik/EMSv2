import React, { useState, useEffect } from 'react';
import { apiClient } from '../services/api';

function UserManagement() {
    const [users, setUsers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [showForm, setShowForm] = useState(false);
    const [editUser, setEditUser] = useState(null);
    const [form, setForm] = useState({ username: '', display_name: '', email: '', role: 'viewer', domain: '' });
    const [filter, setFilter] = useState('all');
    const [activityUser, setActivityUser] = useState(null);
    const [activities, setActivities] = useState([]);

    useEffect(() => { loadUsers(); }, []);

    const loadUsers = async () => {
        try {
            const res = await apiClient.get('/admin/users');
            const data = res.data.users || [];
            setUsers(Array.isArray(data) ? data : []);
        } catch (err) { console.error('Failed to load users:', err); }
        finally { setLoading(false); }
    };

    const saveUser = async () => {
        try {
            if (editUser) {
                await apiClient.put(`/admin/users/${editUser.user_id}`, form);
            } else {
                await apiClient.post('/admin/users', form);
            }
            setShowForm(false); setEditUser(null);
            setForm({ username: '', display_name: '', email: '', role: 'viewer', domain: '' });
            loadUsers();
        } catch (err) { alert('Failed: ' + (err.response?.data?.message || err.message)); }
    };

    const toggleUserStatus = async (userId, currentStatus) => {
        try {
            await apiClient.put(`/admin/users/${userId}`, { is_active: !currentStatus });
            loadUsers();
        } catch (err) { alert('Failed: ' + (err.response?.data?.message || err.message)); }
    };

    const viewActivity = async (user) => {
        setActivityUser(user);
        try {
            const res = await apiClient.get(`/admin/users/${user.user_id}/activity`);
            const data = res.data.events || [];
            setActivities(Array.isArray(data) ? data : []);
        } catch { setActivities([]); }
    };

    const filteredUsers = users.filter(u => {
        if (filter === 'active') return u.is_active;
        if (filter === 'inactive') return !u.is_active;
        return true;
    });

    const roleColors = { admin: '#d32f2f', operator: '#f57c00', viewer: '#1976d2' };

    if (loading) return <div className="spinner"></div>;

    return (
        <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <h1>User Management</h1>
                <button onClick={() => { setShowForm(true); setEditUser(null); setForm({ username: '', display_name: '', email: '', role: 'viewer', domain: '' }); }}
                    style={{ padding: '10px 20px', background: 'var(--primary-color)', color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer', fontWeight: '600' }}>
                    + Create User
                </button>
            </div>

            <div style={{ display: 'flex', gap: '10px', marginBottom: '20px' }}>
                {['all', 'active', 'inactive'].map(f => (
                    <button key={f} onClick={() => setFilter(f)} style={{
                        padding: '8px 16px', borderRadius: '20px', border: 'none', cursor: 'pointer',
                        background: filter === f ? 'var(--primary-color)' : 'var(--bg-tertiary)',
                        color: filter === f ? '#fff' : 'var(--text-primary)', fontWeight: '600', textTransform: 'capitalize'
                    }}>{f}</button>
                ))}
            </div>

            <div className="card" style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                    <thead>
                        <tr style={{ borderBottom: '2px solid var(--border-color)' }}>
                            <th style={thStyle}>Username</th>
                            <th style={thStyle}>Display Name</th>
                            <th style={thStyle}>Email</th>
                            <th style={thStyle}>Role</th>
                            <th style={thStyle}>Status</th>
                            <th style={thStyle}>Last Login</th>
                            <th style={thStyle}>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filteredUsers.map(user => (
                            <tr key={user.user_id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                                <td style={{ ...tdStyle, fontWeight: '600' }}>{user.username}</td>
                                <td style={tdStyle}>{user.display_name || '—'}</td>
                                <td style={tdStyle}>{user.email || '—'}</td>
                                <td style={tdStyle}>
                                    <span style={{ padding: '3px 10px', borderRadius: '10px', fontSize: '0.8rem', fontWeight: '600', color: '#fff', background: roleColors[user.role] || '#666' }}>
                                        {user.role}
                                    </span>
                                </td>
                                <td style={tdStyle}>
                                    <span style={{ color: user.is_active ? '#2e7d32' : '#d32f2f', fontWeight: '600' }}>
                                        {user.is_active ? '● Active' : '● Inactive'}
                                    </span>
                                </td>
                                <td style={tdStyle}>{user.last_login ? new Date(user.last_login).toLocaleString() : 'Never'}</td>
                                <td style={tdStyle}>
                                    <button onClick={() => { setEditUser(user); setForm(user); setShowForm(true); }}
                                        style={{ ...btnStyle, background: '#1976d2' }}>Edit</button>
                                    <button onClick={() => toggleUserStatus(user.user_id, user.is_active)}
                                        style={{ ...btnStyle, background: user.is_active ? '#d32f2f' : '#2e7d32', marginLeft: '5px' }}>
                                        {user.is_active ? 'Deactivate' : 'Activate'}
                                    </button>
                                    <button onClick={() => viewActivity(user)}
                                        style={{ ...btnStyle, background: '#7b1fa2', marginLeft: '5px' }}>Activity</button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>

            {/* Create/Edit Modal */}
            {showForm && (
                <div style={modalOverlay}>
                    <div style={modalBox}>
                        <h2>{editUser ? 'Edit User' : 'Create User'}</h2>
                        {['username', 'display_name', 'email', 'domain'].map(field => (
                            <div key={field} style={{ marginBottom: '12px' }}>
                                <label style={{ display: 'block', marginBottom: '4px', fontWeight: '600', textTransform: 'capitalize' }}>{field.replace('_', ' ')}</label>
                                <input value={form[field] || ''} onChange={e => setForm({ ...form, [field]: e.target.value })}
                                    style={inputStyle} />
                            </div>
                        ))}
                        <label style={{ display: 'block', marginBottom: '4px', fontWeight: '600' }}>Role</label>
                        <select value={form.role} onChange={e => setForm({ ...form, role: e.target.value })} style={inputStyle}>
                            <option value="admin">Admin</option>
                            <option value="operator">Operator</option>
                            <option value="viewer">Viewer</option>
                        </select>
                        <div style={{ display: 'flex', gap: '10px', marginTop: '20px', justifyContent: 'flex-end' }}>
                            <button onClick={() => setShowForm(false)} style={{ ...btnStyle, background: '#555' }}>Cancel</button>
                            <button onClick={saveUser} style={{ ...btnStyle, background: 'var(--primary-color)' }}>Save</button>
                        </div>
                    </div>
                </div>
            )}

            {/* Activity Modal */}
            {activityUser && (
                <div style={modalOverlay}>
                    <div style={{ ...modalBox, maxWidth: '600px' }}>
                        <h2>Activity: {activityUser.username}</h2>
                        {activities.length === 0 ? <p>No activity recorded.</p> :
                            activities.map((ev, i) => (
                                <div key={i} style={{ padding: '10px 0', borderBottom: '1px solid var(--border-color)' }}>
                                    <div style={{ fontWeight: '600' }}>{ev.event_type}</div>
                                    <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                                        {new Date(ev.timestamp).toLocaleString()} • by {ev.performed_by || 'system'}
                                    </div>
                                    {ev.notes && <div style={{ fontSize: '0.85rem', marginTop: '4px' }}>{ev.notes}</div>}
                                </div>
                            ))
                        }
                        <div style={{ textAlign: 'right', marginTop: '20px' }}>
                            <button onClick={() => setActivityUser(null)} style={{ ...btnStyle, background: 'var(--primary-color)' }}>Close</button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

const thStyle = { textAlign: 'left', padding: '12px 10px', fontSize: '0.85rem', color: 'var(--text-secondary)' };
const tdStyle = { padding: '10px', fontSize: '0.9rem' };
const btnStyle = { padding: '5px 12px', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontSize: '0.8rem', fontWeight: '600' };
const inputStyle = { width: '100%', padding: '10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-primary)', color: 'var(--text-primary)', marginBottom: '5px' };
const modalOverlay = { position: 'fixed', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000 };
const modalBox = { background: 'var(--bg-secondary)', borderRadius: '12px', padding: '30px', maxWidth: '450px', width: '90%', boxShadow: '0 10px 40px rgba(0,0,0,0.3)' };

export default UserManagement;
