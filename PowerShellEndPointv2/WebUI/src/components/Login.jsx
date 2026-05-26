import React from 'react';
import { useLogin } from '../hooks/useLogin';
import { ShieldCheck, Network, Server } from 'lucide-react';

function Login({ onLogin }) {
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
                    <fieldset style={{ marginBottom: '20px', border: 'none', padding: 0 }}>
                        <legend style={{ fontWeight: 600, padding: 0, marginBottom: '10px' }}>Authentication Method</legend>
                        <div style={{ display: 'flex', gap: '12px', marginTop: '10px' }}>
                            {providers.map((p) => {
                                const meta = providerMeta[p.Name];
                                const selected = provider === p.Name;

                                return (
                                    <button
                                        key={p.Name}
                                        type="button"
                                        onClick={() => setProvider(p.Name)}
                                        aria-pressed={selected}
                                        style={{
                                            flex: 1,
                                            cursor: 'pointer',
                                            padding: '14px',
                                            borderRadius: '8px',
                                            textAlign: 'center',
                                            border: selected ? '2px solid #1a237e' : '1px solid #ccc',
                                            background: selected ? '#eef2ff' : '#fff',
                                            color: 'inherit'
                                        }}
                                    >
                                        <div style={{ marginBottom: '6px' }}>{meta?.icon}</div>
                                        <div style={{ fontWeight: 600 }}>{meta?.label || p.Name}</div>
                                    </button>
                                );
                            })}
                        </div>
                    </fieldset>
                )}

                <form onSubmit={handleSubmit}>
                    <div className="form-group">
                        <label htmlFor="login-username">Username</label>
                        <input
                            id="login-username"
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
                        <label htmlFor="login-password">Password</label>
                        <input
                            id="login-password"
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
