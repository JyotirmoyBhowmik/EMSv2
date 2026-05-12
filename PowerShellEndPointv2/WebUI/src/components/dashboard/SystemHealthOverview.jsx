import React from 'react';
import InfoIcon from './InfoIcon';

const SystemHealthOverview = ({ stats }) => {
    const totalHealth =
        (stats.excellentCount || 0) +
        (stats.goodCount || 0) +
        (stats.fairCount || 0) +
        (stats.poorCount || 0);

    const getWidth = (value) => {
        if (!totalHealth) return 0;
        return `${(value / totalHealth) * 100}%`;
    };

    return (
        <div className="card">
            <h3 style={{ marginBottom: '20px', fontSize: '1.1rem', color: '#64748b' }}>
                System Health Overview
                <InfoIcon text="Aggregated health score based on security compliance, uptime, and hardware alerts." />
            </h3>
            <div
                style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
                    gap: '25px'
                }}
            >
                <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                        <span style={{ fontWeight: 600, color: '#475569' }}>
                            Excellent
                            <InfoIcon text="Fully healthy: 100% compliant and active telemetry." />
                        </span>
                        <strong style={{ color: '#16a34a', fontSize: '1.1rem' }}>
                            {stats.excellentCount || 0}
                        </strong>
                    </div>
                    <div className="health-score-bar">
                        <div
                            className="health-score-fill health-excellent"
                            style={{ width: getWidth(stats.excellentCount || 0) }}
                        ></div>
                    </div>
                </div>

                <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                        <span style={{ fontWeight: 600, color: '#475569' }}>
                            Good
                            <InfoIcon text="Minor gaps: Mostly compliant with 1-2 non-critical missing data points." />
                        </span>
                        <strong style={{ color: '#2563eb', fontSize: '1.1rem' }}>
                            {stats.goodCount || 0}
                        </strong>
                    </div>
                    <div className="health-score-bar">
                        <div
                            className="health-score-fill health-good"
                            style={{ width: getWidth(stats.goodCount || 0) }}
                        ></div>
                    </div>
                </div>

                <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                        <span style={{ fontWeight: 600, color: '#475569' }}>
                            Fair
                            <InfoIcon text="Warning: Significant policy violations or outdated inventory data." />
                        </span>
                        <strong style={{ color: '#ca8a04', fontSize: '1.1rem' }}>
                            {stats.fairCount || 0}
                        </strong>
                    </div>
                    <div className="health-score-bar">
                        <div
                            className="health-score-fill health-fair"
                            style={{ width: getWidth(stats.fairCount || 0) }}
                        ></div>
                    </div>
                </div>

                <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', alignItems: 'center' }}>
                        <span style={{ fontWeight: 600, color: '#475569' }}>
                            Poor
                            <InfoIcon text="Critical: Major security vulnerabilities or failed management connectivity." />
                        </span>
                        <strong style={{ color: '#dc2626', fontSize: '1.1rem' }}>
                            {stats.poorCount || 0}
                        </strong>
                    </div>
                    <div className="health-score-bar">
                        <div
                            className="health-score-fill health-poor"
                            style={{ width: getWidth(stats.poorCount || 0) }}
                        ></div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default SystemHealthOverview;
