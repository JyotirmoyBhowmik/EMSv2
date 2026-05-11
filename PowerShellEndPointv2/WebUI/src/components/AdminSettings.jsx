import React, { useState, useEffect } from 'react';
import { adminService } from '../services/api';

const categoryColors = {
    Scanning:       { bg: '#eff6ff', border: '#bfdbfe', badge: '#2563eb' },
    Security:       { bg: '#f0fdf4', border: '#bbf7d0', badge: '#16a34a' },
    Reporting:      { bg: '#fff7ed', border: '#fed7aa', badge: '#ea580c' },
    Notifications:  { bg: '#fdf4ff', border: '#e9d5ff', badge: '#9333ea' },
    Administration: { bg: '#fef2f2', border: '#fecaca', badge: '#dc2626' }
};

function ToggleSwitch({ enabled, onChange, disabled }) {
    return (
        <button
            onClick={onChange}
            disabled={disabled}
            aria-pressed={enabled}
            style={{
                position: 'relative', width: 48, height: 26, borderRadius: 13,
                border: 'none', cursor: disabled ? 'not-allowed' : 'pointer',
                background: enabled ? 'linear-gradient(135deg,#16a34a,#4ade80)' : '#d1d5db',
                transition: 'background 0.25s', outline: 'none', flexShrink: 0,
                opacity: disabled ? 0.6 : 1
            }}
        >
            <span style={{
                position: 'absolute', top: 3, left: enabled ? 25 : 3,
                width: 20, height: 20, borderRadius: '50%',
                background: '#fff', boxShadow: '0 1px 4px rgba(0,0,0,0.25)',
                transition: 'left 0.25s'
            }} />
        </button>
    );
}

function InfoIcon({ text }) {
    return (
        <span className="tooltip-container" style={{ marginLeft: '6px', cursor: 'help', verticalAlign: 'middle', display: 'inline-flex' }}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.6 }}>
                <circle cx="12" cy="12" r="10"></circle>
                <line x1="12" y1="16" x2="12" y2="12"></line>
                <line x1="12" y1="8" x2="12.01" y2="8"></line>
            </svg>
            <span className="tooltip-text">{text}</span>
        </span>
    );
}

function AdminSettings() {
    const [features, setFeatures]     = useState([]);
    const [loading, setLoading]       = useState(true);
    const [saving, setSaving]         = useState(null);
    const [message, setMessage]       = useState(null);
    const [activeTab, setActiveTab]   = useState('all');

    const categories = ['all', ...Object.keys(categoryColors)];

    useEffect(() => { loadFeatures(); }, []);

    const loadFeatures = async () => {
        setLoading(true);
        try {
            const data = await adminService.getSettings();
            setFeatures(data);
        } catch (err) {
            console.error('Failed to load settings:', err);
            setMessage({ type: 'error', text: 'Could not load settings from server.' });
        } finally {
            setLoading(false);
        }
    };

    const toggleFeature = async (featureKey, currentValue) => {
        setSaving(featureKey);
        try {
            await adminService.updateSetting(featureKey, !currentValue);
            setFeatures(prev =>
                prev.map(f => f.feature_key === featureKey ? { ...f, enabled: !currentValue } : f)
            );
            setMessage({ type: 'success', text: `Feature "${featureKey}" ${!currentValue ? 'enabled' : 'disabled'}.` });
            setTimeout(() => setMessage(null), 3000);
        } catch (err) {
            setMessage({ type: 'error', text: 'Failed to update feature: ' + (err.response?.data?.message || err.message) });
        } finally {
            setSaving(null);
        }
    };

    const visibleFeatures = features.filter(f => activeTab === 'all' || f.category === activeTab);
    const grouped = categories.slice(1).reduce((acc, cat) => {
        const items = visibleFeatures.filter(f => f.category === cat);
        if (items.length) acc[cat] = items;
        return acc;
    }, {});
    const ungrouped = activeTab === 'all' ? [] : visibleFeatures;

    return (
        <div className="admin-settings-container">
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
            {/* Header */}
            <div style={{ marginBottom: 24 }}>
                <h1 style={{ margin: 0, fontSize: '1.6rem', fontWeight: 700, color: '#0f172a' }}>
                    Settings &amp; Features
                </h1>
                <p style={{ margin: '6px 0 0', color: '#64748b', fontSize: '0.9rem' }}>
                    Enable or disable system features. Changes take effect immediately.
                </p>
            </div>

            {/* Notification */}
            {message && (
                <div style={{
                    marginBottom: 16, padding: '12px 16px', borderRadius: 8,
                    background: message.type === 'success' ? '#f0fdf4' : '#fef2f2',
                    border: `1px solid ${message.type === 'success' ? '#bbf7d0' : '#fecaca'}`,
                    color: message.type === 'success' ? '#166534' : '#991b1b',
                    fontSize: '0.875rem', display: 'flex', alignItems: 'center', gap: 8
                }}>
                    {message.type === 'success' ? '✅' : '⚠️'} {message.text}
                </div>
            )}

            {/* Tab bar */}
            <div style={{ display: 'flex', gap: 6, marginBottom: 24, flexWrap: 'wrap' }}>
                {categories.map(cat => {
                    const count = cat === 'all' ? features.length : features.filter(f => f.category === cat).length;
                    const col = categoryColors[cat];
                    return (
                        <button
                            key={cat}
                            onClick={() => setActiveTab(cat)}
                            style={{
                                padding: '7px 16px', borderRadius: 20, border: 'none',
                                cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                                background: activeTab === cat ? (col?.badge || '#1e293b') : '#f1f5f9',
                                color: activeTab === cat ? '#fff' : '#64748b',
                                transition: 'all 0.15s'
                            }}
                        >
                            {cat === 'all' ? 'All' : cat} ({count})
                        </button>
                    );
                })}
            </div>

            {loading ? (
                <div style={{ textAlign: 'center', padding: 60, color: '#94a3b8' }}>Loading features…</div>
            ) : (
                activeTab === 'all'
                    ? Object.entries(grouped).map(([cat, items]) => (
                        <FeatureCard key={cat} category={cat} features={items} saving={saving} onToggle={toggleFeature} />
                    ))
                    : <FeatureCard category={activeTab} features={ungrouped} saving={saving} onToggle={toggleFeature} />
            )}

            {!loading && features.length === 0 && (
                <div style={{ textAlign: 'center', padding: 60, color: '#94a3b8' }}>
                    No features configured in the database.
                </div>
            )}

            {/* ── Service Credentials Section ── */}
            <CredentialManager />

            {/* ── Environment Config Section ── */}
            <EnvironmentManager />
        </div>
    );
}

function FeatureCard({ category, features, saving, onToggle }) {
    const col = categoryColors[category] || { bg: '#f8fafc', border: '#e2e8f0', badge: '#64748b' };
    const enabledCount = features.filter(f => f.enabled).length;

    const catDesc = {
        Scanning: "Control the frequency and depth of endpoint inventory scans.",
        Security: "Manage authentication, RBAC, and system-wide security policies.",
        Reporting: "Configure automated reports and data export schedules.",
        Notifications: "Set up email alerts and system health notifications.",
        Administration: "Core system management and database maintenance tools."
    };

    return (
        <div style={{
            marginBottom: 20, borderRadius: 12, border: `1px solid ${col.border}`,
            background: '#fff', overflow: 'hidden'
        }}>
            <div style={{
                padding: '14px 20px', background: col.bg,
                borderBottom: `1px solid ${col.border}`,
                display: 'flex', alignItems: 'center', justifyContent: 'space-between'
            }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <span style={{
                        width: 10, height: 10, borderRadius: '50%', background: col.badge, display: 'inline-block'
                    }} />
                    <span style={{ fontWeight: 700, color: '#0f172a', fontSize: '0.95rem' }}>
                        {category}
                        <InfoIcon text={catDesc[category] || `Manage ${category} related features.`} />
                    </span>
                </div>
                <span style={{
                    fontSize: '0.75rem', fontWeight: 600, color: col.badge,
                    background: '#fff', padding: '3px 10px', borderRadius: 12, border: `1px solid ${col.border}`
                }}>
                    {enabledCount}/{features.length} enabled
                </span>
            </div>

            {features.map((f, idx) => (
                <div key={f.feature_key} style={{
                    display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                    padding: '14px 20px',
                    borderBottom: idx < features.length - 1 ? '1px solid #f1f5f9' : 'none'
                }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontWeight: 600, color: '#1e293b', marginBottom: 2, fontSize: '0.875rem' }}>
                            {f.feature_name}
                            <InfoIcon text={f.description || "No additional details available."} />
                        </div>
                        <div style={{ fontSize: '0.8rem', color: '#94a3b8' }}>{f.description}</div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginLeft: 20 }}>
                        <span style={{
                            fontSize: '0.75rem', fontWeight: 600,
                            color: f.enabled ? '#16a34a' : '#94a3b8'
                        }}>
                            {saving === f.feature_key ? '...' : (f.enabled ? 'ON' : 'OFF')}
                        </span>
                        <ToggleSwitch
                            enabled={f.enabled}
                            disabled={saving === f.feature_key}
                            onChange={() => onToggle(f.feature_key, f.enabled)}
                        />
                    </div>
                </div>
            ))}
        </div>
    );
}

function CredentialManager() {
    const [credentials, setCredentials] = useState([]);
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [saving, setSaving] = useState(false);
    const [testing, setTesting] = useState(false);
    const [msg, setMsg] = useState(null);

    useEffect(() => {
        adminService.getCredentials().then(setCredentials).catch(() => {});
    }, []);

    const handleSave = async () => {
        if (!username || !password) { setMsg({ type: 'error', text: 'Username and password are required.' }); return; }
        setSaving(true);
        try {
            await adminService.saveCredentials('ScanService', username, password);
            setMsg({ type: 'success', text: 'Scan service credential saved and encrypted.' });
            setPassword('');
            const c = await adminService.getCredentials();
            setCredentials(c);
        } catch (err) {
            setMsg({ type: 'error', text: err?.response?.data?.message || 'Failed to save credential.' });
        } finally { setSaving(false); setTimeout(() => setMsg(null), 4000); }
    };

    const handleTest = async () => {
        setTesting(true);
        try {
            const res = await adminService.testCredentials('ScanService');
            setMsg({ type: res.success ? 'success' : 'error', text: res.message || 'Test completed.' });
        } catch (err) {
            setMsg({ type: 'error', text: 'Test failed: ' + (err?.response?.data?.message || err.message) });
        } finally { setTesting(false); setTimeout(() => setMsg(null), 5000); }
    };

    const existing = credentials.find(c => c.credential_type === 'ScanService');

    return (
        <div style={{ marginTop: 32, borderRadius: 12, border: '1px solid #e2e8f0', background: '#fff', overflow: 'hidden' }}>
            <div style={{ padding: '14px 20px', background: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ fontSize: '1.2rem' }}>🔐</span>
                <span style={{ fontWeight: 700, color: '#0f172a', fontSize: '0.95rem' }}>Scan Service Account</span>
                <InfoIcon text="Set a domain service account that the scan engine uses to remotely connect to endpoints via CIM/DCOM. Credentials are encrypted with DPAPI." />
            </div>
            <div style={{ padding: 20 }}>
                {existing && (
                    <div style={{ marginBottom: 16, padding: '10px 14px', background: '#f0fdf4', border: '1px solid #bbf7d0', borderRadius: 8, fontSize: '0.85rem', color: '#166534' }}>
                        ✅ Current: <strong>{existing.username}</strong> — Last updated: {existing.updated_at ? new Date(existing.updated_at).toLocaleString() : 'N/A'}
                    </div>
                )}
                {msg && (
                    <div style={{ marginBottom: 12, padding: '10px 14px', borderRadius: 8, background: msg.type === 'success' ? '#f0fdf4' : '#fef2f2', border: `1px solid ${msg.type === 'success' ? '#bbf7d0' : '#fecaca'}`, color: msg.type === 'success' ? '#166534' : '#991b1b', fontSize: '0.85rem' }}>
                        {msg.text}
                    </div>
                )}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: 4 }}>Service Username</label>
                        <input type="text" value={username} onChange={e => setUsername(e.target.value)} placeholder="DOMAIN\svc_ems_scan" style={{ width: '100%', padding: '10px 12px', border: '1px solid #e2e8f0', borderRadius: 8, fontSize: '0.875rem', boxSizing: 'border-box' }} />
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: 4 }}>Service Password</label>
                        <input type="password" value={password} onChange={e => setPassword(e.target.value)} placeholder="••••••••" style={{ width: '100%', padding: '10px 12px', border: '1px solid #e2e8f0', borderRadius: 8, fontSize: '0.875rem', boxSizing: 'border-box' }} />
                    </div>
                </div>
                <div style={{ display: 'flex', gap: 10 }}>
                    <button onClick={handleSave} disabled={saving} style={{ padding: '10px 20px', background: '#2563eb', color: '#fff', border: 'none', borderRadius: 8, fontWeight: 600, cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1 }}>
                        {saving ? 'Encrypting & Saving...' : '🔒 Save Credential'}
                    </button>
                    {existing && (
                        <button onClick={handleTest} disabled={testing} style={{ padding: '10px 20px', background: '#f1f5f9', color: '#475569', border: '1px solid #e2e8f0', borderRadius: 8, fontWeight: 600, cursor: testing ? 'not-allowed' : 'pointer' }}>
                            {testing ? 'Testing...' : '🧪 Test Connection'}
                        </button>
                    )}
                </div>
                <p style={{ marginTop: 12, fontSize: '0.78rem', color: '#94a3b8' }}>
                    Credentials are encrypted using DPAPI (Windows Data Protection API) and stored in the database. They can only be decrypted on this server by the same service account.
                </p>
            </div>
        </div>
    );
}

function EnvironmentManager() {
    const [config, setConfig] = useState([]);
    const [newKey, setNewKey] = useState('');
    const [newValue, setNewValue] = useState('');
    const [newDesc, setNewDesc] = useState('');
    const [saving, setSaving] = useState(false);
    const [msg, setMsg] = useState(null);

    useEffect(() => {
        adminService.getEnvironmentConfig().then(setConfig).catch(() => {});
    }, []);

    const handleSave = async () => {
        if (!newKey || !newValue) { setMsg({ type: 'error', text: 'Key and value are required.' }); return; }
        setSaving(true);
        try {
            await adminService.saveEnvironmentConfig(newKey, newValue, newDesc);
            setMsg({ type: 'success', text: `Variable '${newKey}' saved.` });
            setNewKey(''); setNewValue(''); setNewDesc('');
            const c = await adminService.getEnvironmentConfig();
            setConfig(c);
        } catch (err) {
            setMsg({ type: 'error', text: err?.response?.data?.message || 'Failed to save.' });
        } finally { setSaving(false); setTimeout(() => setMsg(null), 4000); }
    };

    const presets = ['DB_PASSWORD', 'JWT_SECRET', 'API_PORT', 'AD_BIND_PASSWORD', 'SMTP_PASSWORD'];

    return (
        <div style={{ marginTop: 24, borderRadius: 12, border: '1px solid #e2e8f0', background: '#fff', overflow: 'hidden' }}>
            <div style={{ padding: '14px 20px', background: '#f8fafc', borderBottom: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ fontSize: '1.2rem' }}>⚙️</span>
                <span style={{ fontWeight: 700, color: '#0f172a', fontSize: '0.95rem' }}>Environment Configuration</span>
                <InfoIcon text="Manage encrypted environment variables. Sensitive values (containing 'password', 'secret', 'key', 'token') are automatically encrypted." />
            </div>
            <div style={{ padding: 20 }}>
                {msg && (
                    <div style={{ marginBottom: 12, padding: '10px 14px', borderRadius: 8, background: msg.type === 'success' ? '#f0fdf4' : '#fef2f2', border: `1px solid ${msg.type === 'success' ? '#bbf7d0' : '#fecaca'}`, color: msg.type === 'success' ? '#166534' : '#991b1b', fontSize: '0.85rem' }}>
                        {msg.text}
                    </div>
                )}

                {config.length > 0 && (
                    <div style={{ marginBottom: 16 }}>
                        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' }}>
                            <thead>
                                <tr style={{ background: '#f8fafc', borderBottom: '2px solid #e2e8f0' }}>
                                    <th style={{ padding: '10px 12px', textAlign: 'left', fontWeight: 700, color: '#64748b', fontSize: '0.75rem', textTransform: 'uppercase' }}>Key</th>
                                    <th style={{ padding: '10px 12px', textAlign: 'left', fontWeight: 700, color: '#64748b', fontSize: '0.75rem', textTransform: 'uppercase' }}>Value</th>
                                    <th style={{ padding: '10px 12px', textAlign: 'left', fontWeight: 700, color: '#64748b', fontSize: '0.75rem', textTransform: 'uppercase' }}>Description</th>
                                    <th style={{ padding: '10px 12px', textAlign: 'left', fontWeight: 700, color: '#64748b', fontSize: '0.75rem', textTransform: 'uppercase' }}>Updated</th>
                                </tr>
                            </thead>
                            <tbody>
                                {config.map((c, i) => (
                                    <tr key={c.key || i} style={{ borderBottom: '1px solid #f1f5f9' }}>
                                        <td style={{ padding: '10px 12px', fontWeight: 600, color: '#1e293b' }}><code>{c.key}</code></td>
                                        <td style={{ padding: '10px 12px', color: c.isSensitive ? '#94a3b8' : '#1e293b', fontFamily: 'monospace' }}>
                                            {c.isSensitive ? (
                                                <span style={{ background: '#f1f5f9', padding: '2px 8px', borderRadius: 4 }}>🔒 Encrypted</span>
                                            ) : c.value}
                                        </td>
                                        <td style={{ padding: '10px 12px', color: '#64748b' }}>{c.description || '—'}</td>
                                        <td style={{ padding: '10px 12px', color: '#94a3b8', fontSize: '0.8rem', whiteSpace: 'nowrap' }}>{c.updatedAt ? new Date(c.updatedAt).toLocaleDateString() : '—'}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 12, marginBottom: 12 }}>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: 4 }}>Variable Name</label>
                        <select value={newKey} onChange={e => setNewKey(e.target.value)} style={{ width: '100%', padding: '10px 12px', border: '1px solid #e2e8f0', borderRadius: 8, fontSize: '0.875rem', background: '#fff' }}>
                            <option value="">Select or type...</option>
                            {presets.map(p => <option key={p} value={p}>{p}</option>)}
                        </select>
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: 4 }}>Value</label>
                        <input type={newKey.match(/password|secret|key|token/i) ? 'password' : 'text'} value={newValue} onChange={e => setNewValue(e.target.value)} placeholder="Enter value..." style={{ width: '100%', padding: '10px 12px', border: '1px solid #e2e8f0', borderRadius: 8, fontSize: '0.875rem', boxSizing: 'border-box' }} />
                    </div>
                    <div>
                        <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: 4 }}>Description</label>
                        <input type="text" value={newDesc} onChange={e => setNewDesc(e.target.value)} placeholder="Optional description..." style={{ width: '100%', padding: '10px 12px', border: '1px solid #e2e8f0', borderRadius: 8, fontSize: '0.875rem', boxSizing: 'border-box' }} />
                    </div>
                </div>
                <button onClick={handleSave} disabled={saving} style={{ padding: '10px 20px', background: '#2563eb', color: '#fff', border: 'none', borderRadius: 8, fontWeight: 600, cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1 }}>
                    {saving ? 'Saving...' : '💾 Save Variable'}
                </button>
            </div>
        </div>
    );
}

export default AdminSettings;
