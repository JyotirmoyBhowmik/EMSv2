import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { dashboardService } from '../services/api';

import ComplianceClassification from './dashboard/ComplianceClassification';
import SystemHealthOverview from './dashboard/SystemHealthOverview';
import ScanStatusCard from './dashboard/ScanStatusCard';
import PerformanceMetrics from './dashboard/PerformanceMetrics';

function Dashboard() {
    const navigate = useNavigate();

    const [stats, setStats] = useState({
        totalScans: 0,
        healthyEndpoints: 0,
        criticalAlerts: 0,
        uniqueEndpoints: 0,
        completedScans: 0,
        failedScans: 0,
        inProgressScans: 0,
        averageScanTime: null,
        lastScan: null,
        excellentCount: 0,
        goodCount: 0,
        fairCount: 0,
        poorCount: 0,
        totalComputers: 0,
        activeComputers: 0,
        compliantEndpoints: 0,
        partialCompliantEndpoints: 0,
        collectionFailedEndpoints: 0,
        biosPasswordUnknownEndpoints: 0,
        dellBiosUnknownEndpoints: 0,
        metricWarningEndpoints: 0
    });

    const [range, setRange] = useState('all');
    const [loading, setLoading] = useState(true);

    const loadStats = useCallback(async () => {
        try {
            const raw = await dashboardService.getStats(range);
            const data = raw?.stats ? raw.stats : raw || {};

            setStats({
                totalScans: data.totalScans ?? 0,
                healthyEndpoints: data.healthyEndpoints ?? 0,
                criticalAlerts: data.criticalAlerts ?? 0,
                uniqueEndpoints: data.uniqueEndpoints ?? 0,
                completedScans: data.completedScans ?? 0,
                failedScans: data.failedScans ?? 0,
                inProgressScans: data.inProgressScans ?? 0,
                averageScanTime: data.averageScanTime ?? null,
                lastScan: data.lastScan ?? null,
                excellentCount: data.excellentCount ?? 0,
                goodCount: data.goodCount ?? 0,
                fairCount: data.fairCount ?? 0,
                poorCount: data.poorCount ?? 0,
                totalComputers: data.totalComputers ?? 0,
                activeComputers: data.activeComputers ?? 0,
                compliantEndpoints: data.compliantEndpoints ?? 0,
                partialCompliantEndpoints: data.partialCompliantEndpoints ?? 0,
                collectionFailedEndpoints: data.collectionFailedEndpoints ?? 0,
                biosPasswordUnknownEndpoints: data.biosPasswordUnknownEndpoints ?? data.dellBiosUnknownEndpoints ?? 0,
                dellBiosUnknownEndpoints: data.dellBiosUnknownEndpoints ?? 0,
                metricWarningEndpoints: data.metricWarningEndpoints ?? 0
            });
        } catch (error) {
            console.error('Failed to load stats:', error);
        } finally {
            setLoading(false);
        }
    }, [range]);

    useEffect(() => {
        loadStats();
        const interval = setInterval(loadStats, 30000);
        return () => clearInterval(interval);
    }, [loadStats]);

    if (loading) {
        return <div className="spinner"></div>;
    }

    return (
        <div className="dashboard-container">
            <style>{`
                .tooltip-container { position: relative; display: inline-block; }
                .tooltip-text {
                    visibility: hidden; width: 220px; background-color: #1e293b; color: #fff;
                    text-align: center; border-radius: 6px; padding: 8px 12px; position: absolute;
                    z-index: 10; bottom: 125%; left: 50%; margin-left: -110px; opacity: 0;
                    transition: opacity 0.3s; font-size: 0.75rem; font-weight: 400; line-height: 1.4;
                    box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); pointer-events: none;
                }
                .tooltip-container:hover .tooltip-text { visibility: visible; opacity: 1; }
                .tooltip-text::after {
                    content: ""; position: absolute; top: 100%; left: 50%; margin-left: -5px;
                    border-width: 5px; border-style: solid; border-color: #1e293b transparent transparent transparent;
                }
                .stat-card:hover { transform: translateY(-2px); transition: transform 0.2s; }
            `}</style>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '30px' }}>
                <h1 style={{ margin: 0, fontWeight: 700, color: '#0f172a' }}>Dashboard</h1>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <span style={{ fontSize: '0.875rem', fontWeight: 600, color: '#64748b' }}>Observation Window:</span>
                    <select 
                        className="form-control" 
                        value={range} 
                        onChange={(e) => setRange(e.target.value)}
                        style={{ width: '160px', marginBottom: 0 }}
                    >
                        <option value="all">All Time</option>
                        <option value="today">Today (So far)</option>
                        <option value="24h">Last 24 Hours</option>
                        <option value="7d">Last 7 Days</option>
                        <option value="30d">Last 30 Days</option>
                    </select>
                </div>
            </div>

            <ComplianceClassification stats={stats} navigate={navigate} />

            <SystemHealthOverview stats={stats} />

            <div
                style={{
                    display: 'grid',
                    gridTemplateColumns: '1fr 1fr',
                    gap: '20px',
                    marginTop: '20px'
                }}
            >
                <ScanStatusCard stats={stats} />
                <PerformanceMetrics stats={stats} />
            </div>
        </div>
    );
}

export default Dashboard;
