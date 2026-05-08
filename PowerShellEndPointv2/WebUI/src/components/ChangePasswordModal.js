import React, { useState } from 'react';
import { authService } from '../services/api';

const ChangePasswordModal = ({ isOpen, onClose }) => {
    const [oldPassword, setOldPassword] = useState('');
    const [newPassword, setNewPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [success, setSuccess] = useState(false);

    if (!isOpen) return null;

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');
        setSuccess(false);

        if (newPassword !== confirmPassword) {
            setError('New passwords do not match');
            return;
        }

        if (newPassword.length < 8) {
            setError('Password must be at least 8 characters long');
            return;
        }

        setLoading(true);
        try {
            const res = await authService.changePassword(oldPassword, newPassword);
            if (res.success) {
                setSuccess(true);
                setOldPassword('');
                setNewPassword('');
                setConfirmPassword('');
                setTimeout(() => onClose(), 2000);
            } else {
                setError(res.message || 'Failed to change password');
            }
        } catch (err) {
            setError(err.response?.data?.message || 'Server error occurred');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="modal-overlay">
            <div className="modal-content" style={{ maxWidth: '400px' }}>
                <div className="modal-header">
                    <h2>Change Password</h2>
                    <button className="close-btn" onClick={onClose}>&times;</button>
                </div>
                
                <form onSubmit={handleSubmit} className="modal-body">
                    {error && <div className="alert alert-danger">{error}</div>}
                    {success && <div className="alert alert-success">Password updated successfully!</div>}
                    
                    <div className="form-group">
                        <label>Current Password</label>
                        <input 
                            type="password" 
                            className="form-control" 
                            value={oldPassword}
                            onChange={(e) => setOldPassword(e.target.value)}
                            required
                            disabled={loading || success}
                        />
                    </div>
                    
                    <div className="form-group">
                        <label>New Password</label>
                        <input 
                            type="password" 
                            className="form-control" 
                            value={newPassword}
                            onChange={(e) => setNewPassword(e.target.value)}
                            required
                            disabled={loading || success}
                        />
                    </div>
                    
                    <div className="form-group">
                        <label>Confirm New Password</label>
                        <input 
                            type="password" 
                            className="form-control" 
                            value={confirmPassword}
                            onChange={(e) => setConfirmPassword(e.target.value)}
                            required
                            disabled={loading || success}
                        />
                    </div>
                    
                    <div className="modal-footer">
                        <button type="button" className="btn" onClick={onClose} disabled={loading}>
                            Cancel
                        </button>
                        <button type="submit" className="btn btn-primary" disabled={loading || success}>
                            {loading ? 'Updating...' : 'Update Password'}
                        </button>
                    </div>
                </form>
            </div>
            
            <style jsx>{`
                .modal-overlay {
                    position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                    background: rgba(0,0,0,0.5); display: flex; align-items: center;
                    justify-content: center; z-index: 2000;
                }
                .modal-content {
                    background: var(--bg-secondary); border-radius: 8px;
                    width: 90%; padding: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.2);
                }
                .modal-header {
                    display: flex; justify-content: space-between; align-items: center;
                    margin-bottom: 20px; border-bottom: 1px solid var(--border-color);
                    padding-bottom: 10px;
                }
                .close-btn {
                    background: none; border: none; font-size: 1.5rem;
                    cursor: pointer; color: var(--text-secondary);
                }
                .form-group { margin-bottom: 15px; }
                .form-group label { display: block; margin-bottom: 5px; color: var(--text-secondary); }
                .modal-footer {
                    display: flex; justify-content: flex-end; gap: 10px;
                    margin-top: 20px; padding-top: 15px; border-top: 1px solid var(--border-color);
                }
                .alert { padding: 10px; border-radius: 4px; margin-bottom: 15px; font-size: 0.9rem; }
                .alert-danger { background: #fee2e2; color: #991b1b; }
                .alert-success { background: #dcfce7; color: #166534; }
            `}</style>
        </div>
    );
};

export default ChangePasswordModal;
