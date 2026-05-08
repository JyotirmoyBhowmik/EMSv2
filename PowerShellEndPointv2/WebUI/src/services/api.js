import axios from 'axios';

// ── Auto-detect API URL ─────────────────────────────
// This ensures the frontend knows where to find the PowerShell API
const getBaseUrl = () => {
    if (process.env.REACT_APP_API_URL) return process.env.REACT_APP_API_URL;
    
    const { hostname, protocol, port, origin } = window.location;
    
    // If running via 'npm start' or 'serve' on port 3000, assume API is on 5000
    if (port === '3000') {
        return `${protocol}//${hostname}:5000`;
    }
    
    // If running on standard port (e.g. IIS), assume API is at /api
    return `${origin}/api`;
};

const API_BASE_URL = getBaseUrl();

// ── Axios Instance ──────────────────────────────────
const apiClient = axios.create({
    baseURL: API_BASE_URL,
    timeout: 60000,
    headers: { 'Content-Type': 'application/json' }
});

// ── Request Interceptor ─────────────────────────────
apiClient.interceptors.request.use((config) => {
    const token = localStorage.getItem('auth_token') || localStorage.getItem('token');
    
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }

    try {
        const user = JSON.parse(localStorage.getItem('user') || 'null');
        if (user?.username) config.headers['X-EMS-Username'] = user.username;
        if (user?.role)     config.headers['X-EMS-Role']     = user.role;
        if (Array.isArray(user?.groups)) {
            config.headers['X-EMS-Groups'] = user.groups.join(';');
        }
    } catch { /* ignore */ }
    
    return config;
});

// ── Response Interceptor ────────────────────────────
apiClient.interceptors.response.use(
    (response) => response,
    async (error) => {
        if (error.response?.status === 401) {
            localStorage.clear();
            if (window.location.pathname !== '/login') window.location.href = '/login';
        }
        return Promise.reject(error);
    }
);

// ── Helper Methods ──────────────────────────────────
// Note: We remove the leading /api from URLs here because it's in the baseURL or handled by the listener
const get = (url, params) => apiClient.get(url, { params }).then(r => r.data);
const post = (url, data, config = {}) => apiClient.post(url, data, config).then(r => r.data);
const put = (url, data) => apiClient.put(url, data).then(r => r.data);
const del = (url) => apiClient.delete(url).then(r => r.data);

// ── Services ────────────────────────────────────────

export const authService = {
    login: (username, password, provider = 'Standalone') => 
        post('/api/auth/login', { username, password, provider }).then(data => {
            if (data.success && data.user) {
                localStorage.setItem('auth_token', data.token || '');
                localStorage.setItem('user', JSON.stringify(data.user));
            }
            return data;
        }),
    logout: () => { localStorage.clear(); window.location.href = '/login'; },
    getProviders: () => get('/api/auth/providers'),
    validate: () => get('/api/auth/validate'),
};

export const scanService = {
    scanSingle:     (target, protocol) => post('/api/scan/single', { target, protocol }),
    scanBulk:       (targets, protocol) => post('/api/scan/bulk', { targets, protocol }),
    getScanStatus:  (scanId) => get('/api/scan/status', { scanId }),
    getScanTrace:   (scanId) => get('/api/scan/trace',  { scanId }),
    archiveScan:    (scanId, reason) => post(`/api/results/${scanId}/archive`, { reason }),
};

export const dashboardService = {
    getStats: (range) => get('/api/dashboard/stats', { range }).then(res => res?.stats || res || {}),
};

export const resultsService = {
    getAll: (params) => get('/api/results', params).then(res => res?.results || res || []),
    getById: (id) => get(`/api/results/${id}`),
};

export const adminService = {
    getSettings: () => get('/api/admin/settings').then(res => res?.features || []),
    updateSetting: (key, enabled) => put(`/api/admin/settings/${key}`, { enabled }),
    getEndpoints: () => get('/api/computers').then(res => res?.computers || []),
    getUsers: () => get('/api/admin/users').then(res => res?.users || []),
    getAuditLogs: (params) => get('/api/admin/audit', params).then(res => res?.logs || []),
    getRebootStatus: () => get('/api/admin/reboot-status').then(res => res?.endpoints || []),
    getConnectors: () => get('/api/admin/connectors').then(res => {
        const list = res?.connectors || res;
        return Array.isArray(list) ? list : [];
    }),
};

export const computerService = {
    getAll: (params) => get('/api/computers', params).then(res => res?.computers || res || []),
    getByName: (name) => get(`/api/computers/${encodeURIComponent(name)}`),
};

export const inventoryService = {
    getLifecycle: () => get('/api/inventory/lifecycle'),
};

export const historicalService = {
    getHeatmap:     (params) => get('/api/historical/heatmap', params),
    getTimeline:    (computer) => get(`/api/historical/timeline/${computer}`),
    getDriftAnalysis: () => get('/api/historical/drift'),
};

export const errorLogService = {
    logFrontendError: async (message, stack, url) => {
        try {
            await post('/api/audit/frontend-error', { message, stack, url, userAgent: navigator.userAgent });
        } catch { /* silent */ }
    }
};

export { apiClient };
export default apiClient;
