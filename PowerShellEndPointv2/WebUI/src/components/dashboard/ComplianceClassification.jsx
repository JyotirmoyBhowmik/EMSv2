import React from 'react';
import { motion } from 'framer-motion';
import InfoIcon from './InfoIcon';

const clickableCardStyle = {
    border: 'none',
    textAlign: 'left',
    width: '100%',
    cursor: 'pointer'
};

const ComplianceClassification = ({ stats, navigate }) => {
    return (
        <>
            <h3 style={{ marginBottom: '15px', fontSize: '1.1rem', color: '#64748b' }}>
                Compliance Classification
                <InfoIcon text="Real-time breakdown of endpoint security and collection status across the enterprise." />
            </h3>

            <motion.div
                className="stat-cards"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, staggerChildren: 0.1 }}
            >
                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #2e7d32, #66bb6a)'
                    }}
                    onClick={() => navigate('/results?view=compliant')}
                >
                    <div className="stat-label">
                        COMPLIANT ENDPOINTS
                        <InfoIcon text="Endpoints meeting 100% of defined enterprise security policies." />
                    </div>
                    <div className="stat-value">{stats.compliantEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        All required compliance fields valid
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #f57c00, #ffb74d)'
                    }}
                    onClick={() => navigate('/results?view=partial')}
                >
                    <div className="stat-label">
                        PARTIAL COMPLIANT
                        <InfoIcon text="Missing one or more secondary security configurations or policy data." />
                    </div>
                    <div className="stat-value">{stats.partialCompliantEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        One or more required fields missing or unknown
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #d32f2f, #ef5350)'
                    }}
                    onClick={() => navigate('/results?view=partial&issue=collectionFailed')}
                >
                    <div className="stat-label">
                        COLLECTION FAILED
                        <InfoIcon text="Inventory collection was blocked by firewall, RPC failure, or system being offline." />
                    </div>
                    <div className="stat-value">{stats.collectionFailedEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        Inventory collection failed / RPC unavailable
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #5e35b1, #7e57c2)'
                    }}
                    onClick={() => navigate('/results?view=partial&issue=biosPasswordUnknown')}
                >
                    <div className="stat-label">
                        BIOS PASSWORD
                        <InfoIcon text="The status of hardware-level passwords (Admin/System) cannot be verified." />
                    </div>
                    <div className="stat-value">{stats.biosPasswordUnknownEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        Power-on/Admin password status unknown
                    </div>
                </button>

                <button
                    type="button"
                    className="stat-card"
                    style={{
                        ...clickableCardStyle,
                        background: 'linear-gradient(135deg, #1976d2, #64b5f6)'
                    }}
                    onClick={() => navigate('/results?view=partial&issue=metricWarning')}
                >
                    <div className="stat-label">
                        METRIC WARNING
                        <InfoIcon text="System identity is confirmed, but performance/health telemetry collection failed." />
                    </div>
                    <div className="stat-value">{stats.metricWarningEndpoints || 0}</div>
                    <div style={{ fontSize: '0.85rem', marginTop: '8px', opacity: 0.9 }}>
                        Inventory completed but metric collection failed
                    </div>
                </button>
            </motion.div>
        </>
    );
};

export default ComplianceClassification;
