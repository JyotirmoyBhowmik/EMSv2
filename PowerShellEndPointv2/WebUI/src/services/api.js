import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://10.192.6.109:5000';

// ─────────────────────────────────────────────────
// Axios Instance
// ─────────────────────────────────────────────────
const apiClient = axios.create({
    baseURL: API_BASE_URL,
    timeout: 30000,
    headers: { 'Content-Type': 'application/json' }
});

// ─────────────────────────────────────────────────
// Request Interceptor — attach auth headers
// ─────────────────────────────────────────────────
apiClient.interceptors.request.use(
    (config) => {
        const token = localStorage.getItem('auth_token');
        if (token) config.headers.Authorization = `Bearer ${token}`;

        try {
            const user = JSON.parse(localStorage.getItem('user') || 'null');
            if (user?.username) config.headers['X-EMS-Username'] = user.username;
            if (user?.role)     config.headers['X-EMS-Role']     = user.role;
            if (Array.isArray(user?.groups) && user.groups.length > 0) {
                config.headers['X-EMS-Groups'] = user.groups.join(';');
            }
        } catch { /* ignore parse errors */ }

        return config;
    },
    (error) => Promise.reject(error)
);

// ─────────────────────────────────────────────────
// Response Interceptor — global 401 handling
// ─────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────
// Auth Service
// ─────────────────────────────────────────────────
export const authService = {
    login: async (username, password, provider = null) => {
        const response = await apiClient.post('/auth/login', { username, password, provider });
        if (response.data.success) {
            if (response.data.token) localStorage.setItem('auth_token', response.data.token);
            localStorage.setItem('user', JSON.stringify(response.data.user));
            if (provider) localStorage.setItem('authProvider', provider);
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
        } catch { return false; }
    },
    getCurrentUser: () => {
        try { return JSON.parse(localStorage.getItem('user') || 'null'); } catch { return null; }
    },
    isAuthenticated: () => !!localStorage.getItem('auth_token'),
    getProviders: async () => {
        const response = await apiClient.get('/auth/providers');
        return response.data;
    },
    changePassword: async (oldPassword, newPassword) => {
        const response = await apiClient.post('/auth/change-password', { oldPassword, newPassword });
        return response.data;
    }
};

// ─────────────────────────────────────────────────
// Dashboard Service
// ─────────────────────────────────────────────────
export const dashboardService = {
    getStats: async (range = 'all') => {
        const response = await apiClient.get('/api/dashboard/stats', { params: { range } });
        const raw = response.data || {};
        const stats = raw.stats || raw || {};
        const collectionFailed = Number(stats.collectionFailedEndpoints ?? raw.collectionFailedEndpoints ?? 0);
        const partialRaw = Number(stats.partialCompliantEndpoints ?? raw.partialCompliantEndpoints ?? 0);
        const partialAdjusted = Math.max(partialRaw - collectionFailed, 0);
        return {
            ...raw, ...stats,
            partialCompliantEndpoints: partialAdjusted,
            collectionFailedEndpoints: collectionFailed,
            stats: { ...stats, partialCompliantEndpoints: partialAdjusted, collectionFailedEndpoints: collectionFailed }
        };
    }
};

// ─────────────────────────────────────────────────
// Scan Service
// ─────────────────────────────────────────────────
export const scanService = {
    scanSingle: async (target, protocol = null) => (await apiClient.post('/scan/single', { target, protocol })).data,
    scanBulk: async (targets, protocol = null) => (await apiClient.post('/scan/bulk', { targets, protocol })).data,
    getScanStatus: async (scanId) => (await apiClient.get('/scan/status', { params: { scanId } })).data,
    getScanResult: async (scanId) => (await apiClient.get('/scan/result', { params: { scanId } })).data,
    getScanTrace:  async (scanId) => (await apiClient.get('/scan/trace',  { params: { scanId } })).data
};

// ─────────────────────────────────────────────────
// Results Service
// ─────────────────────────────────────────────────
export const resultsService = {
    getResults: async (params = {}) => (await apiClient.get('/results', { params })).data,
    getResultById: async (id) => (await apiClient.get(`/results/${id}`)).data,
    archiveResult: async (id, reason = '') => (await apiClient.post(`/results/${id}/archive`, { reason })).data,
    restoreResult: async (id) => (await apiClient.post(`/results/${id}/restore`, {})).data
};

// ─────────────────────────────────────────────────
// Compliance Service
// ─────────────────────────────────────────────────
export const complianceService = {
    getCompliant: async () => (await apiClient.get('/api/compliance/compliant')).data?.results || [],
    getPartial:   async () => (await apiClient.get('/api/compliance/partial')).data?.results || [],
    getNonCompliant: async () => {
        try { return (await apiClient.get('/api/compliance/non-compliant')).data?.results || []; }
        catch { return []; }
    },
    getUnknown: async () => {
        try { return (await apiClient.get('/api/compliance/unknown')).data?.results || []; }
        catch { return []; }
    }
};

// ─────────────────────────────────────────────────
// Computer Service
// ─────────────────────────────────────────────────
export const computerService = {
    getComputers: async (limit = 100) => (await apiClient.get(`/computers?limit=${limit}`)).data,
    getComputer: async (name) => (await apiClient.get(`/computers/${encodeURIComponent(name)}`)).data,
    registerComputer: async (data) => (await apiClient.post('/computers', data)).data
};

// ─────────────────────────────────────────────────
// Admin Service  ← NEW: centralizes all /admin/* calls
// ─────────────────────────────────────────────────
export const adminService = {
    // Feature Toggles / Settings
    getSettings: async () => {
        const res = await apiClient.get('/admin/settings');
        return Array.isArray(res.data?.features) ? res.data.features : [];
    },
    updateSetting: async (featureKey, enabled) => {
        const res = await apiClient.put(`/admin/settings/${featureKey}`, { enabled });
        return res.data;
    },

    // Users
    getUsers: async () => {
        const res = await apiClient.get('/admin/users');
        return Array.isArray(res.data?.users) ? res.data.users : [];
    },
    createUser: async (userData) => (await apiClient.post('/admin/users', userData)).data,
    updateUser: async (userId, userData) => (await apiClient.put(`/admin/users/${userId}`, userData)).data,
    deleteUser: async (userId) => (await apiClient.delete(`/admin/users/${userId}`)).data,

    // Reboot Status
    getRebootStatus: async () => {
        const res = await apiClient.get('/admin/reboot-status');
        return Array.isArray(res.data?.endpoints) ? res.data.endpoints : [];
    },

    // Connector Health
    getConnectors: async () => {
        const res = await apiClient.get('/admin/connectors');
        return Array.isArray(res.data?.connectors) ? res.data.connectors : [];
    },

    // Audit Logs
    getAuditLogs: async (type = 'api', limit = 200) => {
        const res = await apiClient.get('/admin/audit', { params: { type, limit } });
        return Array.isArray(res.data?.logs) ? res.data.logs : [];
    },

    // System Errors (frontend crash logs)
    getSystemErrors: async (limit = 200) => {
        const res = await apiClient.get('/admin/audit', { params: { type: 'ERROR', limit } });
        const logs = Array.isArray(res.data?.logs) ? res.data.logs : [];
        return logs.filter(l => l.method === 'ERROR' || (l.error_message && l.error_message.startsWith('[FRONTEND')));
    },

    // Endpoint Lifecycle (computers inventory)
    getEndpoints: async () => {
        const res = await apiClient.get('/computers');
        return Array.isArray(res.data?.computers) ? res.data.computers : [];
    }
};

// ─────────────────────────────────────────────────
// Error Logging Service
// ─────────────────────────────────────────────────
export const errorLogService = {
    logFrontendError: async (message, stack, url) => {
        try {
            await apiClient.post('/audit/frontend-error', {
                message, stack, url,
                userAgent: navigator.userAgent
            });
        } catch { /* silent — don't cause infinite loops */ }
    }
};

// ─────────────────────────────────────────────────
// Exports
// ─────────────────────────────────────────────────
export { apiClient };

// Default export = apiClient so existing `import api from ...` still works
export default apiClient;
