import React, { useState } from 'react';
import { authService } from '../services/api';
import { Eye, EyeOff } from 'lucide-react';

const PasswordInput = ({ id, label, value, onChange, disabled }) => {
    const [showPassword, setShowPassword] = useState(false);

    return (
        <div className="form-group">
            <label htmlFor={id}>{label}</label>
            <div style={{ position: 'relative' }}>
                <input
                    id={id}
                    type={showPassword ? 'text' : 'password'}
                    className="form-control"
                    value={value}
                    onChange={onChange}
                    required
                    disabled={disabled}
                    style={{ paddingRight: '40px' }}
                />
                <button
                    type="button"
                    aria-label={showPassword ? "Hide password" : "Show password"}
                    onClick={() => setShowPassword(!showPassword)}
                    style={{
                        position: 'absolute', right: '10px', top: '50%',
                        transform: 'translateY(-50%)', background: 'none',
                        border: 'none', cursor: 'pointer', color: '#64748b',
                        display: 'flex', alignItems: 'center', padding: '4px'
                    }}
                >
                    {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
                </button>
            </div>
        </div>
    );
};

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
            <div
                className="modal-content"
                style={{ maxWidth: '400px' }}
                role="dialog"
                aria-modal="true"
                aria-labelledby="change-password-title"
            >
                <div className="modal-header">
                    <h2 id="change-password-title">Change Password</h2>
                    <button className="close-btn" aria-label="Close change password modal" onClick={onClose}>&times;</button>
                </div>
                
                <form onSubmit={handleSubmit} className="modal-body">
                    {error && <div className="alert alert-danger">{error}</div>}
                    {success && <div className="alert alert-success">Password updated successfully!</div>}
                    
                    <PasswordInput
                        id="oldPassword"
                        label="Current Password"
                        value={oldPassword}
                        onChange={(e) => setOldPassword(e.target.value)}
                        disabled={loading || success}
                    />
                    
                    <PasswordInput
                        id="newPassword"
                        label="New Password"
                        value={newPassword}
                        onChange={(e) => setNewPassword(e.target.value)}
                        disabled={loading || success}
                    />
                    
                    <PasswordInput
                        id="confirmPassword"
                        label="Confirm New Password"
                        value={confirmPassword}
                        onChange={(e) => setConfirmPassword(e.target.value)}
                        disabled={loading || success}
                    />
                    
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
