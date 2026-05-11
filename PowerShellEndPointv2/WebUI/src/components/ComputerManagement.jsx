import React, { useState, useEffect } from 'react';
import { computerService } from '../services/api';

function ComputerManagement() {
    const [computers, setComputers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [showAddForm, setShowAddForm] = useState(false);
    const [newComputer, setNewComputer] = useState({
        name: '',
        ip: '',
        type: 'Desktop'
    });

    useEffect(() => {
        fetchComputers();
    }, []);

    const fetchComputers = async () => {
        try {
            setLoading(true);
            const response = await computerService.getComputers(200);
            setComputers(response.computers || []);
            setError('');
        } catch (err) {
            setError('Failed to load computers');
            console.error(err);
        } finally {
            setLoading(false);
        }
    };

    const handleAddComputer = async (e) => {
        e.preventDefault();
        try {
            await computerService.registerComputer(newComputer);
            setShowAddForm(false);
            setNewComputer({ name: '', ip: '', type: 'Desktop' });
            fetchComputers();
        } catch (err) {
            setError('Failed to register computer');
            console.error(err);
        }
    };

    const formatLastSeen = (timestamp) => {
        if (!timestamp) return 'Never';
        const date = new Date(timestamp);
        const now = new Date();
        const diffMs = now - date;
        const diffMins = Math.floor(diffMs / 60000);

        if (diffMins < 60) return `${diffMins}m ago`;
        if (diffMins < 1440) return `${Math.floor(diffMins / 60)}h ago`;
        return `${Math.floor(diffMins / 1440)}d ago`;
    };

    const getStatusColor = (lastSeen) => {
        if (!lastSeen) return 'gray';
        const diffMins = (new Date() - new Date(lastSeen)) / 60000;
        if (diffMins < 60) return 'green';
        if (diffMins < 1440) return 'yellow';
        return 'red';
    };

    if (loading) {
        return <div className="loading">Loading computers...</div>;
    }

    return (
        <div className="page-container">
            <div className="page-header">
                <h1>Computer Management</h1>
                <button
                    className="btn btn-primary"
                    onClick={() => setShowAddForm(!showAddForm)}
                >
                    {showAddForm ? 'Cancel' : '+ Add Computer'}
                </button>
            </div>

            {error && (
                <div className="alert alert-error">{error}</div>
            )}

            {showAddForm && (
                <div className="card" style={{ marginBottom: '20px' }}>
                    <h3>Register New Computer</h3>
                    <form onSubmit={handleAddComputer} className="form-horizontal">
                        <div className="form-row">
                            <div className="form-group">
                                <label>Computer Name</label>
                                <input
                                    type="text"
                                    value={newComputer.name}
                                    onChange={(e) => setNewComputer({ ...newComputer, name: e.target.value })}
                                    placeholder="STANDALONE-PC-01"
                                    required
                                />
                            </div>
                            <div className="form-group">
                                <label>IP Address</label>
                                <input
                                    type="text"
                                    value={newComputer.ip}
                                    onChange={(e) => setNewComputer({ ...newComputer, ip: e.target.value })}
                                    placeholder="192.168.1.100"
                                    required
                                />
                            </div>
                            <div className="form-group">
                                <label>Type</label>
                                <select
                                    value={newComputer.type}
                                    onChange={(e) => setNewComputer({ ...newComputer, type: e.target.value })}
                                >
                                    <option>Desktop</option>
                                    <option>Laptop</option>
                                    <option>Server</option>
                                    <option>Workstation</option>
                                </select>
                            </div>
                        </div>
                        <button type="submit" className="btn btn-success">Register</button>
                    </form>
                </div>
            )}

            <div className="stats-grid" style={{ marginBottom: '20px' }}>
                <div className="stat-card">
                    <h3>{computers.length}</h3>
                    <p>Total Computers</p>
                </div>
                <div className="stat-card">
                    <h3>{computers.filter(c => c.is_active).length}</h3>
                    <p>Active</p>
                </div>
                <div className="stat-card">
                    <h3>{computers.filter(c => c.is_domain_joined).length}</h3>
                    <p>Domain Joined</p>
                </div>
                <div className="stat-card">
                    <h3>{computers.filter(c => !c.is_domain_joined).length}</h3>
                    <p>Standalone</p>
                </div>
            </div>

            <div className="card">
                <table className="data-table">
                    <thead>
                        <tr>
                            <th>Status</th>
                            <th>Computer Name</th>
                            <th>IP Address</th>
                            <th>Type</th>
                            <th>Domain</th>
                            <th>OS</th>
                            <th>Last Seen</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {computers.map((computer) => (
                            <tr key={computer.computer_name}>
                                <td>
                                    <span
                                        className="status-dot"
                                        style={{ backgroundColor: getStatusColor(computer.last_seen) }}
                                        title={computer.is_active ? 'Active' : 'Inactive'}
                                    ></span>
                                </td>
                                <td><strong>{computer.computer_name}</strong></td>
                                <td>{computer.ip_address || 'N/A'}</td>
                                <td>{computer.computer_type || 'Unknown'}</td>
                                <td>
                                    {computer.is_domain_joined ? (
                                        <span className="badge badge-info">{computer.domain || 'Domain'}</span>
                                    ) : (
                                        <span className="badge badge-warning">Standalone</span>
                                    )}
                                </td>
                                <td>{computer.operating_system || 'N/A'}</td>
                                <td>{formatLastSeen(computer.last_seen)}</td>
                                <td>
                                    <a href={`#/computers/${computer.computer_name}`} className="btn btn-sm">
                                        View Details
                                    </a>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>

                {computers.length === 0 && (
                    <div className="empty-state">
                        <p>No computers found. Add a computer to get started.</p>
                    </div>
                )}
            </div>
        </div>
    );
}

export default ComputerManagement;
