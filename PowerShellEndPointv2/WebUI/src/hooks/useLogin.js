import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { authService } from '../services/api';

export function useLogin(onLogin) {
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
                sessionStorage.setItem('authProvider', response.provider || provider);

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

    return {
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
    };
}
