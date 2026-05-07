import React, { useState, useEffect } from 'react';
import { apiClient } from '../services/api';

function AdminSettings() {
    const [features, setFeatures] = useState([]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(null);

    const categories = ['Scanning', 'Security', 'Reporting', 'Notifications', 'Administration'];
    const categoryColors = {
        Scanning: '#1976d2',
        Security: '#2e7d32',
        Reporting: '#f57c00',
        Notifications: '#7b1fa2',
        Administration: '#c62828'
    };

    useEffect(() => { loadFeatures(); }, []);

    const loadFeatures = async () => {
        try {
            const res = await apiClient.get('/admin/settings');
            const data = res.data.features || [];
            setFeatures(Array.isArray(data) ? data : []);
        } catch (err) {
            console.error('Failed to load settings:', err);
            setFeatures([]);
        } finally {
            setLoading(false);
        }
    };

    const toggleFeature = async (featureKey, currentValue) => {
        setSaving(featureKey);
        try {
            await apiClient.put(`/admin/settings/${featureKey}`, { enabled: !currentValue });
            setFeatures(prev =>
                prev.map(f => f.feature_key === featureKey ? { ...f, enabled: !currentValue } : f)
            );
        } catch (err) {
            alert('Failed to update feature: ' + (err.response?.data?.message || err.message));
        } finally {
            setSaving(null);
        }
    };

    if (loading) return <div className="spinner"></div>;

    return (
        <div>
            <h1 style={{ marginBottom: '10px' }}>Admin Settings</h1>
            <p style={{ color: 'var(--text-secondary)', marginBottom: '30px' }}>
                Enable or disable system features. Changes take effect immediately.
            </p>

            {categories.map(cat => {
                const catFeatures = features.filter(f => f.category === cat);
                if (catFeatures.length === 0) return null;

                return (
                    <div key={cat} className="card" style={{ marginBottom: '20px' }}>
                        <h3 style={{
                            marginBottom: '20px',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '10px'
                        }}>
                            <span style={{
                                width: '12px', height: '12px', borderRadius: '50%',
                                background: categoryColors[cat] || '#666', display: 'inline-block'
                            }}></span>
                            {cat}
                        </h3>

                        {catFeatures.map(feature => (
                            <div key={feature.feature_key} style={{
                                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                                padding: '12px 0', borderBottom: '1px solid var(--border-color)'
                            }}>
                                <div>
                                    <div style={{ fontWeight: '600', marginBottom: '4px' }}>
                                        {feature.feature_name}
                                    </div>
                                    <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                                        {feature.description}
                                    </div>
                                </div>
                                <button
                                    onClick={() => toggleFeature(feature.feature_key, feature.enabled)}
                                    disabled={saving === feature.feature_key}
                                    style={{
                                        minWidth: '60px', padding: '6px 16px', border: 'none',
                                        borderRadius: '20px', cursor: 'pointer', fontWeight: '600',
                                        fontSize: '0.8rem', transition: 'all 0.3s',
                                        background: feature.enabled
                                            ? 'linear-gradient(135deg, #2e7d32, #66bb6a)' : '#555',
                                        color: '#fff',
                                        opacity: saving === feature.feature_key ? 0.5 : 1
                                    }}
                                >
                                    {saving === feature.feature_key ? '...' : (feature.enabled ? 'ON' : 'OFF')}
                                </button>
                            </div>
                        ))}
                    </div>
                );
            })}
        </div>
    );
}

export default AdminSettings;
