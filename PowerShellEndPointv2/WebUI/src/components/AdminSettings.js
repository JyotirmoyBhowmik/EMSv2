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

export default AdminSettings;
