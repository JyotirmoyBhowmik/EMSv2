import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { computerService } from '../services/api';

function ComputerDetails() {
    const { computerName } = useParams();
    const [computer, setComputer] = useState(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [activeTab, setActiveTab] = useState('overview');

    useEffect(() => {
        fetchComputerDetails();
    }, [computerName]);

    const fetchComputerDetails = async () => {
        try {
            setLoading(true);
            const data = await computerService.getComputer(computerName);
            setComputer(data);
            setError('');
        } catch (err) {
            setError('Failed to load computer details');
            console.error(err);
        } finally {
            setLoading(false);
        }
    };

    if (loading) {
        return <div className="loading">Loading computer details...</div>;
    }

    if (error || !computer) {
        return <div className="alert alert-error">{error || 'Computer not found'}</div>;
    }

    const metrics = computer.metrics || {};
    const users = computer.users || [];

    return (
        <div className="page-container">
            <div className="page-header">
                <h1>{computer.computer_name}</h1>
                <span className={`badge ${computer.is_active ? 'badge-success' : 'badge-secondary'}`}>
                    {computer.is_active ? 'Active' : 'Inactive'}
                </span>
            </div>

            <div className="card" style={{ marginBottom: '20px' }}>
                <div className="info-grid">
                    <div>
                        <label>IP Address</label>
                        <p>{computer.ip_address || 'N/A'}</p>
                    </div>
                    <div>
                        <label>MAC Address</label>
                        <p>{computer.mac_address || 'N/A'}</p>
                    </div>
                    <div>
                        <label>Operating System</label>
                        <p>{computer.operating_system || 'Unknown'}</p>
                    </div>
                    <div>
                        <label>OS Version</label>
                        <p>{computer.os_version || 'N/A'}</p>
                    </div>
                    <div>
                        <label>Computer Type</label>
                        <p>{computer.computer_type || 'Unknown'}</p>
                    </div>
                    <div>
                        <label>Domain</label>
                        <p>{computer.is_domain_joined ? computer.domain : 'Standalone'}</p>
                    </div>
                    <div>
                        <label>Location</label>
                        <p>{computer.location || 'Not Set'}</p>
                    </div>
                    <div>
                        <label>Department</label>
                        <p>{computer.department || 'Not Set'}</p>
                    </div>
                </div>
            </div>

            {users.length > 0 && (
                <div className="card" style={{ marginBottom: '20px' }}>
                    <h3>Associated Users</h3>
                    <table className="data-table">
                        <thead>
                            <tr>
                                <th>User ID</th>
                                <th>Display Name</th>
                                <th>Email</th>
                                <th>Primary</th>
                                <th>Last Login</th>
                                <th>Login Count</th>
                            </tr>
                        </thead>
                        <tbody>
                            {users.map((user) => (
                                <tr key={user.id}>
                                    <td>{user.user_id}</td>
                                    <td>{user.user_display_name || 'N/A'}</td>
                                    <td>{user.user_email || 'N/A'}</td>
                                    <td>
                                        {user.is_primary_user && <span className="badge badge-primary">Primary</span>}
                                    </td>
                                    <td>{user.last_login ? new Date(user.last_login).toLocaleString() : 'Never'}</td>
                                    <td>{user.login_count || 0}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            )}

            <div className="tabs">
                <button
                    className={`tab ${activeTab === 'overview' ? 'active' : ''}`}
                    onClick={() => setActiveTab('overview')}
                >
                    Overview
                </button>
                <button
                    className={`tab ${activeTab === 'cpu' ? 'active' : ''}`}
                    onClick={() => setActiveTab('cpu')}
                >
                    CPU
                </button>
                <button
                    className={`tab ${activeTab === 'memory' ? 'active' : ''}`}
                    onClick={() => setActiveTab('memory')}
                >
                    Memory
                </button>
                <button
                    className={`tab ${activeTab === 'disk' ? 'active' : ''}`}
                    onClick={() => setActiveTab('disk')}
                >
                    Disk
                </button>
                <button
                    className={`tab ${activeTab === 'security' ? 'active' : ''}`}
                    onClick={() => setActiveTab('security')}
                >
                    Security
                </button>
            </div>

            <div className="tab-content">
                {activeTab === 'overview' && (
                    <div className="stats-grid">
                        {metrics.CPU && (
                            <div className="stat-card">
                                <h4>CPU Usage</h4>
                                <div className="stat-value">{metrics.CPU.usage_percent?.toFixed(1)}%</div>
                                <p>{metrics.CPU.processor_name}</p>
                                <small>{metrics.CPU.core_count} cores, {metrics.CPU.logical_processors} logical</small>
                            </div>
                        )}
                        {metrics.Memory && (
                            <div className="stat-card">
                                <h4>Memory Usage</h4>
                                <div className="stat-value">{metrics.Memory.usage_percent?.toFixed(1)}%</div>
                                <p>{metrics.Memory.used_gb?.toFixed(1)} GB / {metrics.Memory.total_gb?.toFixed(1)} GB</p>
                            </div>
                        )}
                        {metrics.Updates && (
                            <div className="stat-card">
                                <h4>Windows Updates</h4>
                                <div className="stat-value">{metrics.Updates.pending_updates || 0}</div>
                                <p>Pending Updates</p>
                                {metrics.Updates.reboot_required && <span className="badge badge-warning">Reboot Required</span>}
                            </div>
                        )}
                        {metrics.Antivirus && (
                            <div className="stat-card">
                                <h4>Antivirus</h4>
                                <div className="stat-value">{metrics.Antivirus.av_enabled ? '✓' : '✗'}</div>
                                <p>{metrics.Antivirus.av_product || 'Not Installed'}</p>
                                <small>Definitions: {metrics.Antivirus.definitions_date ? new Date(metrics.Antivirus.definitions_date).toLocaleDateString() : 'Unknown'}</small>
                            </div>
                        )}
                    </div>
                )}

                {activeTab === 'cpu' && metrics.CPU && (
                    <div className="card">
                        <h3>CPU Information</h3>
                        <div className="info-grid">
                            <div>
                                <label>Processor</label>
                                <p>{metrics.CPU.processor_name}</p>
                            </div>
                            <div>
                                <label>Current Usage</label>
                                <p>{metrics.CPU.usage_percent?.toFixed(1)}%</p>
                            </div>
                            <div>
                                <label>Physical Cores</label>
                                <p>{metrics.CPU.core_count}</p>
                            </div>
                            <div>
                                <label>Logical Processors</label>
                                <p>{metrics.CPU.logical_processors}</p>
                            </div>
                            <div>
                                <label>Speed</label>
                                <p>{metrics.CPU.processor_speed_mhz} MHz</p>
                            </div>
                        </div>
                    </div>
                )}

                {activeTab === 'memory' && metrics.Memory && (
                    <div className="card">
                        <h3>Memory Information</h3>
                        <div className="info-grid">
                            <div>
                                <label>Total Memory</label>
                                <p>{metrics.Memory.total_gb?.toFixed(2)} GB</p>
                            </div>
                            <div>
                                <label>Used Memory</label>
                                <p>{metrics.Memory.used_gb?.toFixed(2)} GB</p>
                            </div>
                            <div>
                                <label>Available Memory</label>
                                <p>{metrics.Memory.available_gb?.toFixed(2)} GB</p>
                            </div>
                            <div>
                                <label>Usage</label>
                                <p>{metrics.Memory.usage_percent?.toFixed(1)}%</p>
                            </div>
                        </div>
                        <div className="progress-bar" style={{ marginTop: '20px' }}>
                            <div
                                className="progress-fill"
                                style={{ width: `${metrics.Memory.usage_percent}%`, backgroundColor: metrics.Memory.usage_percent > 80 ? '#e74c3c' : '#3498db' }}
                            ></div>
                        </div>
                    </div>
                )}

                {activeTab === 'disk' && metrics.Disks && (
                    <div className="card">
                        <h3>Disk Information</h3>
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Drive</th>
                                    <th>File System</th>
                                    <th>Total</th>
                                    <th>Used</th>
                                    <th>Free</th>
                                    <th>Usage</th>
                                </tr>
                            </thead>
                            <tbody>
                                {metrics.Disks.map((disk, idx) => (
                                    <tr key={idx}>
                                        <td><strong>{disk.drive_letter}:</strong> {disk.is_system_drive && <span className="badge badge-info">System</span>}</td>
                                        <td>{disk.file_system}</td>
                                        <td>{disk.total_gb?.toFixed(1)} GB</td>
                                        <td>{disk.used_gb?.toFixed(1)} GB</td>
                                        <td>{disk.free_gb?.toFixed(1)} GB</td>
                                        <td>
                                            <div className="progress-bar-small">
                                                <div
                                                    className="progress-fill"
                                                    style={{
                                                        width: `${disk.usage_percent}%`,
                                                        backgroundColor: disk.usage_percent > 90 ? '#e74c3c' : disk.usage_percent > 70 ? '#f39c12' : '#27ae60'
                                                    }}
                                                ></div>
                                            </div>
                                            <span>{disk.usage_percent?.toFixed(1)}%</span>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                {activeTab === 'security' && (
                    <div>
                        {metrics.Updates && (
                            <div className="card" style={{ marginBottom: '15px' }}>
                                <h3>Windows Updates</h3>
                                <div className="info-grid">
                                    <div>
                                        <label>Pending Updates</label>
                                        <p>{metrics.Updates.pending_updates || 0}</p>
                                    </div>
                                    <div>
                                        <label>Failed Updates</label>
                                        <p>{metrics.Updates.failed_updates || 0}</p>
                                    </div>
                                    <div>
                                        <label>Auto Update</label>
                                        <p>{metrics.Updates.auto_update_enabled ? 'Enabled' : 'Disabled'}</p>
                                    </div>
                                    <div>
                                        <label>Reboot Required</label>
                                        <p>{metrics.Updates.reboot_required ? 'Yes' : 'No'}</p>
                                    </div>
                                </div>
                            </div>
                        )}

                        {metrics.Antivirus && (
                            <div className="card">
                                <h3>Antivirus Status</h3>
                                <div className="info-grid">
                                    <div>
                                        <label>Product</label>
                                        <p>{metrics.Antivirus.av_product || 'Not Installed'}</p>
                                    </div>
                                    <div>
                                        <label>Version</label>
                                        <p>{metrics.Antivirus.av_version || 'N/A'}</p>
                                    </div>
                                    <div>
                                        <label>Real-Time Protection</label>
                                        <p>{metrics.Antivirus.real_time_protection ? 'Enabled' : 'Disabled'}</p>
                                    </div>
                                    <div>
                                        <label>Definitions Date</label>
                                        <p>{metrics.Antivirus.definitions_date ? new Date(metrics.Antivirus.definitions_date).toLocaleDateString() : 'Unknown'}</p>
                                    </div>
                                </div>
                            </div>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
}

export default ComputerDetails;
