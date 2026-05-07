import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://10.192.6.87:5000';

const apiClient = axios.create({
    baseURL: API_BASE_URL,
    headers: {
        'Content-Type': 'application/json'
    }
});

apiClient.interceptors.request.use(
    (config) => {
        const token = localStorage.getItem('auth_token');

        if (token) {
            config.headers.Authorization = `Bearer ${token}`;
        }

        const userJson = localStorage.getItem('user');

        if (userJson) {
            try {
                const user = JSON.parse(userJson);

                if (user?.username) {
                    config.headers['X-EMS-Username'] = user.username;
                }

                if (user?.role) {
                    config.headers['X-EMS-Role'] = user.role;
                }
            } catch {
            }
        }

        return config;
    },
    (error) => Promise.reject(error)
);

apiClient.interceptors.response.use(
    (response) => response,
    (error) => {
        if (error.response?.status === 401) {
            localStorage.removeItem('auth_token');
            localStorage.removeItem('user');
            localStorage.removeItem('authProvider');
            window.location.href = '/login';
        }

        return Promise.reject(error);
    }
);

export const authService = {
    login: async (username, password, provider = null) => {
        const response = await apiClient.post('/auth/login', {
            username,
            password,
            provider
        });

        if (response.data.success && response.data.token) {
            localStorage.setItem('auth_token', response.data.token);
            localStorage.setItem('user', JSON.stringify(response.data.user));

            if (provider) {
                localStorage.setItem('authProvider', provider);
            }
        }

        return response.data;
    },

    logout: () => {
        localStorage.removeItem('auth_token');
        localStorage.removeItem('user');
        localStorage.removeItem('authProvider');
    },

    validate: async () => {
        try {
            const response = await apiClient.get('/auth/validate');
            return response.data.valid;
        } catch {
            return false;
        }
    },

    getCurrentUser: () => {
        const userJson = localStorage.getItem('user');

        try {
            return userJson ? JSON.parse(userJson) : null;
        } catch {
            return null;
        }
    },

    isAuthenticated: () => {
        return !!localStorage.getItem('auth_token');
    },

    getProviders: async () => {
        const response = await apiClient.get('/auth/providers');
        return response.data;
    }
};

export const dashboardService = {
    getStats: async () => {
        const response = await apiClient.get('/api/dashboard/stats');

        const raw = response.data || {};
        const stats = raw.stats || raw || {};

        const collectionFailed = Number(
            stats.collectionFailedEndpoints ??
            raw.collectionFailedEndpoints ??
            0
        );

        const partialRaw = Number(
            stats.partialCompliantEndpoints ??
            raw.partialCompliantEndpoints ??
            0
        );

        /*
            Dashboard correction:
            Collection Failed is shown as a separate dashboard card and separate result view.
            Therefore Partial Compliant dashboard count must exclude collection failed endpoints.
        */
        const partialAdjusted = Math.max(partialRaw - collectionFailed, 0);

        return {
            ...raw,
            ...stats,
            partialCompliantEndpoints: partialAdjusted,
            collectionFailedEndpoints: collectionFailed,
            stats: {
                ...stats,
                partialCompliantEndpoints: partialAdjusted,
                collectionFailedEndpoints: collectionFailed
            }
        };
    }
};

export const scanService = {
    scanSingle: async (target) => {
        const response = await apiClient.post('/scan/single', { target });
        return response.data;
    },

    scanBulk: async (targets) => {
        const response = await apiClient.post('/scan/bulk', { targets });
        return response.data;
    },

    getScanStatus: async (scanId) => {
        const response = await apiClient.get('/scan/status', {
            params: { scanId }
        });

        return response.data;
    },

    getScanResult: async (scanId) => {
        const response = await apiClient.get('/scan/result', {
            params: { scanId }
        });

        return response.data;
    }
};

export const resultsService = {
    getResults: async (params = {}) => {
        const response = await apiClient.get('/results', { params });
        return response.data;
    },

    getResultById: async (id) => {
        const response = await apiClient.get(`/results/${id}`);
        return response.data;
    },

    archiveResult: async (id, reason = '') => {
        const response = await apiClient.post(`/results/${id}/archive`, { reason });
        return response.data;
    },

    restoreResult: async (id) => {
        const response = await apiClient.post(`/results/${id}/restore`, {});
        return response.data;
    }
};

export const complianceService = {
    getCompliant: async () => {
        const response = await apiClient.get('/api/compliance/compliant');
        return response.data?.results || [];
    },

    getPartial: async () => {
        const response = await apiClient.get('/api/compliance/partial');
        return response.data?.results || [];
    },

    getNonCompliant: async () => {
        const response = await apiClient.get('/api/compliance/non-compliant');
        return response.data?.results || [];
    },

    getUnknown: async () => {
        const response = await apiClient.get('/api/compliance/unknown');
        return response.data?.results || [];
    }
};

export const computerService = {
    getComputers: async (limit = 100) => {
        const response = await apiClient.get(`/computers?limit=${limit}`);
        return response.data;
    },

    getComputer: async (computerName) => {
        const response = await apiClient.get(`/computers/${encodeURIComponent(computerName)}`);
        return response.data;
    },

    registerComputer: async (computerData) => {
        const response = await apiClient.post('/computers', computerData);
        return response.data;
    }
};

export { apiClient };
export default apiClient;


