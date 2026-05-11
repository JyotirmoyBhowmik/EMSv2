import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { authService } from '../services/api';
import { FaUserShield, FaNetworkWired, FaServer } from 'react-icons/fa';

function Login({ onLogin }) {
    const [username, setUsername] = useState('');
    const [password, setPassword] = useState('');
    const [provider, setProvider] = useState('');
    const [providers, setProviders] = useState([]);
    const [providersLoaded, setProvidersLoaded] = useState(false);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const navigate = useNavigate();

    useEffect(() => {
        const fetchProviders = async () => {
            try {
                const response = await authService.getProviders();
                let provs = [];

                if (Array.isArray(response?.providers)) {
                    provs = response.providers;
                } else if (response?.providers) {
                    provs = [response.providers];
                }

                provs.sort((a, b) => (a.Priority ?? 999) - (b.Priority ?? 999));
                setProviders(provs);

                if (response?.defaultProvider) {
                    setProvider(response.defaultProvider);
                } else if (provs.length > 0) {
                    setProvider(provs[0].Name);
                }
            } catch (err) {
                console.error('Provider fetch failed:', err);
                setError('Unable to load authentication providers');
            } finally {
                setProvidersLoaded(true);
            }
        };

        fetchProviders();
    }, []);

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');

        if (!providersLoaded) {
            setError('Authentication providers are still loading. Please wait.');
            return;
        }

        if (!provider) {
            setError('Authentication method not selected');
            return;
        }

        if (!username.trim() || !password.trim()) {
            setError('Username and password are required');
            return;
        }

        setLoading(true);

        try {
            const response = await authService.login(username.trim(), password, provider);

            if (response?.success) {
                localStorage.setItem('auth_token', response.token);
                localStorage.setItem('user', JSON.stringify(response.user));
                localStorage.setItem('authProvider', response.provider || provider);

                if (onLogin) {
                    onLogin(response.user);
                }

                navigate('/dashboard');
            } else {
                setError(response?.message || 'Login failed');
            }
        } catch (err) {
            console.error('Login error', err);
            setError(
                err?.response?.data?.message ||
                'Authentication failed. Only EMS_Admins and EMS_Monitor members are allowed to sign in.'
            );
        } finally {
            setLoading(false);
        }
    };

    const providerMeta = {
        Standalone: {
            label: 'Local Account',
            icon: <FaUserShield size={32} />
        },
        ActiveDirectory: {
            label: 'Active Directory',
            icon: <FaNetworkWired size={32} />
        },
        LDAP: {
            label: 'LDAP',
            icon: <FaServer size={32} />
        }
    };

    const usernamePlaceholder = () => {
        if (provider === 'ActiveDirectory') return 'DOMAIN\\username';
        if (provider === 'LDAP') return 'username or email';
        return 'username';
    };

    return (
        <div
            style={{
                minHeight: '100vh',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                background: 'linear-gradient(135deg, #1a237e 0%, #534bae 100%)',
                padding: '20px'
            }}
        >
            <div
                className="card"
                style={{
                    width: '100%',
                    maxWidth: '460px',
                    background: '#ffffff',
                    borderRadius: '10px',
                    boxShadow: '0 8px 24px rgba(0,0,0,0.18)',
                    padding: '28px'
                }}
            >
                <h2 style={{ marginBottom: '8px', color: '#1e3a8a' }}>
                    Endpoint Monitoring System
                </h2>
                <p style={{ color: '#666', marginBottom: '20px' }}>
                    Sign in to access the dashboard
                </p>

                {error && (
                    <div
                        style={{
                            padding: '12px',
                            marginBottom: '20px',
                            background: '#f8d7da',
                            color: '#721c24',
                            borderRadius: '6px'
                        }}
                    >
                        {error}
                    </div>
                )}

                {providers.length > 1 && (
                    <div style={{ marginBottom: '20px' }}>
                        <label style={{ fontWeight: 600 }}>Authentication Method</label>
                        <div style={{ display: 'flex', gap: '12px', marginTop: '10px' }}>
                            {providers.map((p) => {
                                const meta = providerMeta[p.Name];
                                const selected = provider === p.Name;

                                return (
                                    <div
                                        key={p.Name}
                                        onClick={() => setProvider(p.Name)}
                                        style={{
                                            flex: 1,
                                            cursor: 'pointer',
                                            padding: '14px',
                                            borderRadius: '8px',
                                            textAlign: 'center',
                                            border: selected ? '2px solid #1a237e' : '1px solid #ccc',
                                            background: selected ? '#eef2ff' : '#fff'
                                        }}
                                    >
                                        <div style={{ marginBottom: '6px' }}>{meta?.icon}</div>
                                        <div style={{ fontWeight: 600 }}>{meta?.label || p.Name}</div>
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                )}

                <form onSubmit={handleSubmit}>
                    <div className="form-group">
                        <label>Username</label>
                        <input
                            type="text"
                            className="form-control"
                            placeholder={usernamePlaceholder()}
                            value={username}
                            onChange={(e) => setUsername(e.target.value)}
                            disabled={loading}
                            required
                        />
                    </div>

                    <div className="form-group">
                        <label>Password</label>
                        <input
                            type="password"
                            className="form-control"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            disabled={loading}
                            required
                        />
                    </div>

                    <button
                        type="submit"
                        className="btn btn-primary"
                        style={{ width: '100%', marginTop: '10px' }}
                        disabled={loading || !providersLoaded}
                    >
                        {loading
                            ? 'Signing in...'
                            : !providersLoaded
                            ? 'Loading auth methods...'
                            : 'Sign In'}
                    </button>
                </form>

                <div style={{ marginTop: '20px', textAlign: 'center' }}>
                    <small style={{ color: '#666' }}>
                        Powered by EMS v3.5-Enterprise | Using {providerMeta[provider]?.label || provider || '-'}
                    </small>
                </div>
            </div>
        </div>
    );
}

export default Login;
