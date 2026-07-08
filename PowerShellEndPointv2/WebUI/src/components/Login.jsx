import React, { useState } from 'react';
import { useLogin } from '../hooks/useLogin';
import { ShieldCheck, Network, Server, Eye, EyeOff } from 'lucide-react';

function Login({ onLogin }) {
    const [showPassword, setShowPassword] = useState(false);
    const {
        username,
        setUsername,
        password,
        setPassword,
        provider,
        setProvider,
        providers,
        providersLoaded,
        error,
        loading,
        handleSubmit
    } = useLogin(onLogin);

    const providerMeta = {
        Standalone: {
            label: 'Local Account',
            icon: <ShieldCheck size={32} />
        },
        ActiveDirectory: {
            label: 'Active Directory',
            icon: <Network size={32} />
        },
        LDAP: {
            label: 'LDAP',
            icon: <Server size={32} />
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
                                    <button
                                        type="button"
                                        aria-pressed={selected}
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
                                    </button>
                                );
                            })}
                        </div>
                    </div>
                )}

                <form onSubmit={handleSubmit}>
                    <div className="form-group">
                        <label htmlFor="username">Username</label>
                        <input
                            id="username"
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
                        <label htmlFor="password">Password</label>
                        <div style={{ position: 'relative' }}>
                            <input
                                id="password"
                                type={showPassword ? 'text' : 'password'}
                                className="form-control"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                disabled={loading}
                                required
                                style={{ paddingRight: '40px' }}
                            />
                            <button
                                type="button"
                                aria-label={showPassword ? "Hide password" : "Show password"}
                                onClick={() => setShowPassword(!showPassword)}
                                style={{
                                    position: 'absolute',
                                    right: '10px',
                                    top: '50%',
                                    transform: 'translateY(-50%)',
                                    background: 'none',
                                    border: 'none',
                                    cursor: 'pointer',
                                    color: '#64748b',
                                    display: 'flex',
                                    alignItems: 'center',
                                    padding: '4px'
                                }}
                            >
                                {showPassword ? <EyeOff size={20} /> : <Eye size={20} />}
                            </button>
                        </div>
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
