import React from 'react';

const ScanStatusCard = ({ stats }) => {
    return (
        <div className="card">
            <h3 style={{ marginBottom: '15px' }}>Scan Status</h3>

            <div
                style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    padding: '10px 0',
                    borderBottom: '1px solid var(--border-color)'
                }}
            >
                <span>Completed</span>
                <span className="badge badge-success">{stats.completedScans || 0}</span>
            </div>

            <div
                style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    padding: '10px 0',
                    borderBottom: '1px solid var(--border-color)'
                }}
            >
                <span>Failed</span>
                <span className="badge badge-danger">{stats.failedScans || 0}</span>
            </div>

            <div
                style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    padding: '10px 0'
                }}
            >
                <span>In Progress</span>
                <span className="badge badge-info">{stats.inProgressScans || 0}</span>
            </div>
        </div>
    );
};

export default ScanStatusCard;
