import axios from 'axios';

// ── Auto-detect API URL ─────────────────────────────
// This ensures the frontend knows where to find the PowerShell API
const getBaseUrl = () => {
    if (process.env.REACT_APP_API_URL) return process.env.REACT_APP_API_URL;
    
    const { hostname, protocol, port, origin } = window.location;
    
    // If running via 'npm start' or 'serve' on port 3000, assume API is on 5000
    if (port === '3000') {
        return `${protocol}//${hostname}:5000/api`;
    }
    
    // If running on standard port (e.g. IIS), return origin + /api
    return origin.endsWith('/api') ? origin : `${origin}/api`;
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
        post('/auth/login', { username, password, provider }).then(data => {
            if (data.success && data.user) {
                localStorage.setItem('auth_token', data.token || '');
                localStorage.setItem('user', JSON.stringify(data.user));
            }
            return data;
        }),
    logout: () => { localStorage.clear(); window.location.href = '/login'; },
    getProviders: () => get('/auth/providers'),
    validate: () => get('/auth/validate'),
};

export const scanService = {
    scanSingle:     (target, protocol) => post('/scan/single', { target, protocol }),
    scanBulk:       (targets, protocol) => post('/scan/bulk', { targets, protocol }),
    getScanStatus:  (scanId) => get('/scan/status', { scanId }),
    getScanResult:  (scanId) => get('/scan/result', { scanId }),
    getScanTrace:   (scanId) => get('/scan/trace',  { scanId }),
    archiveScan:    (scanId, reason) => post(`/results/${scanId}/archive`, { reason }),
    restoreScan:    (scanId) => post(`/results/${scanId}/restore`, {}),
};

export const dashboardService = {
    getStats: (range) => get('/dashboard/stats', { range }).then(res => res?.stats || res || {}),
    getSummary: () => get('/dashboard/summary'),
    getTopIssues: () => get('/dashboard/top-issues'),
};

export const resultsService = {
    getAll: (params) => get('/api/results', params).then(res => res?.results || res || []),
    getById: (id) => get(`/api/results/${id}`),
    getLatest: () => get('/api/results/latest'),
};

export const complianceService = {
    getReport: (params) => get('/api/compliance/report', params).then(res => res?.report || res || []),
    getHistory: (params) => get('/api/compliance/history', params).then(res => res?.history || res || []),
};

export const adminService = {
    getSettings: () => get('/api/admin/settings').then(res => res?.features || []),
    updateSetting: (key, enabled) => put(`/api/admin/settings/${key}`, { enabled }),
    getEndpoints: () => get('/api/computers').then(res => res?.computers || []),
    getUsers: () => get('/api/admin/users').then(res => res?.users || []),
    createUser: (data) => post('/api/admin/users', data),
    updateUser: (id, data) => put(`/api/admin/users/${id}`, data),
    deleteUser: (id) => del(`/api/admin/users/${id}`),
    getAuditLogs: (params) => get('/api/admin/audit', params).then(res => res?.logs || []),
    getRebootStatus: () => get('/api/admin/reboot-status').then(res => res?.endpoints || []),
    getConnectors: () => get('/api/admin/connectors').then(res => {
        const list = res?.connectors || res;
        return Array.isArray(list) ? list : [];
    }),
    // SystemErrors.js calls this — was missing, causing runtime crash
    getSystemErrors: () => get('/api/admin/audit', { type: 'ERROR' }).then(res => res?.logs || []),
    // Credential management (Phase 4)
    getCredentials: () => get('/api/admin/credentials').then(res => res?.credentials || []),
    saveCredentials: (type, username, password) => post('/api/admin/credentials', { type, username, password }),
    testCredentials: (type) => post('/api/admin/credentials/test', { type }),
    // Environment config (Phase 4)
    getEnvironmentConfig: () => get('/api/admin/environment').then(res => res?.config || []),
    saveEnvironmentConfig: (key, value, description) => post('/api/admin/environment', { key, value, description }),
};

export const performanceService = {
    getPerformanceReport: (hostname, period = '7d') => get('/api/performance/report', { hostname, period }),
    getResourceUtilization: (hostname, metric, period = '24h') => get('/api/performance/utilization', { hostname, metric, period }),
    getPerformanceAlerts: (params) => get('/api/performance/alerts', params),
};

export const computerService = {
    getAll: (params) => get('/api/computers', params).then(res => res?.computers || res || []),
    getByName: (name) => get(`/api/computers/${encodeURIComponent(name)}`),
};

export const inventoryService = {
    getAll:         (params) => get('/api/inventory', params).then(res => res?.inventory || res || []),
    getByHostname:  (hostname) => get(`/api/inventory/${hostname}`),
    getLifecycle:   () => get('/api/inventory/lifecycle'),
    exportCSV:      (params) => get('/api/inventory/export', params),
};

export const historicalService = {
    getHeatmap:     (params) => get('/api/historical/heatmap', params),
    getTimeline:    (computer) => get(`/api/historical/timeline/${computer}`),
    getComparison:  (computers, period) => post('/api/historical/compare', { computers, period }),
    getDriftAnalysis: () => get('/api/historical/drift'),
    getCutoverReport: (params) => get('/api/historical/cutover', params),
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
