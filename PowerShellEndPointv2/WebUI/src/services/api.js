import ky from 'ky';

// ── Auto-detect API URL ─────────────────────────────
const getBaseUrl = () => {
    if (import.meta.env.VITE_API_URL) return import.meta.env.VITE_API_URL;

    const { hostname, protocol, port, origin } = window.location;

    const isDevPort = port === '3000' || port === '3001' || port === '3002';
    if (isDevPort || (port && port !== '5000' && hostname === 'localhost')) {
        return `${protocol}//${hostname}:5000/api`;
    }

    if (port === '5000') return `${origin}/api`;

    return `${origin}/api`;
};

const API_BASE_URL = getBaseUrl();

// ── Ky Instance ──────────────────────────────────────
const apiClient = ky.create({
    prefixUrl: API_BASE_URL,
    timeout: 60000,
    headers: { 'Content-Type': 'application/json' },
    hooks: {
        beforeRequest: [
            (request) => {
                try {
                    const token = localStorage.getItem('auth_token');
                    if (token) {
                        request.headers.set('Authorization', `Bearer ${token}`);
                    }
                } catch { /* ignore */ }
            },
        ],
        afterResponse: [
            async (_request, _options, response) => {
                if (response.status === 401) {
                    localStorage.clear();
                    if (window.location.pathname !== '/login') window.location.href = '/login';
                }
            },
        ],
    },
});

// ── Helper Methods ──────────────────────────────────
// ky prefixUrl auto-joins; strip leading slash from paths
const get  = (url, params) => apiClient.get(url, { searchParams: params }).json();
const post = (url, data)   => apiClient.post(url, { json: data }).json();
const put  = (url, data)   => apiClient.put(url, { json: data }).json();
const del  = (url)         => apiClient.delete(url).json();

// ── Services ────────────────────────────────────────

export const authService = {
    login: (username, password, provider = 'Standalone') =>
        post('auth/login', { username, password, provider }).then(data => {
            if (data.success && data.user) {
                localStorage.setItem('auth_token', data.token || '');
                localStorage.setItem('user', JSON.stringify(data.user));
            }
            return data;
        }),
    logout: () => { localStorage.clear(); window.location.href = '/login'; },
    getProviders: () => get('auth/providers'),
    validate: () => get('auth/validate'),
};

export const scanService = {
    scanSingle:     (target, protocol) => post('scan/single', { target, protocol }),
    scanBulk:       (targets, protocol) => post('scan/bulk', { targets, protocol }),
    getScanStatus:  (scanId) => get('scan/status', { scanId }),
    getScanResult:  (scanId) => get('scan/result', { scanId }),
    getScanTrace:   (scanId) => get('scan/trace',  { scanId }),
    archiveScan:    (scanId, reason) => post(`results/${scanId}/archive`, { reason }),
    restoreScan:    (scanId) => post(`results/${scanId}/restore`, {}),
};

export const dashboardService = {
    getStats: (range) => get('dashboard/stats', { range }).then(res => res?.stats || res || {}),
    getSummary: () => get('dashboard/summary'),
    getTopIssues: () => get('dashboard/top-issues'),
};

export const resultsService = {
    getAll: (params) => get('results', params).then(res => res?.results || res || []),
    getById: (id) => get(`results/${id}`),
    getLatest: () => get('results/latest'),
};

export const complianceService = {
    getReport: (params) => get('compliance/report', params).then(res => res?.report || res || []),
    getHistory: (params) => get('compliance/history', params).then(res => res?.history || res || []),
};

export const adminService = {
    getSettings: () => get('admin/settings').then(res => res?.features || []),
    updateSetting: (key, enabled) => put(`admin/settings/${key}`, { enabled }),
    getEndpoints: () => get('computers').then(res => res?.computers || []),
    getUsers: () => get('admin/users').then(res => res?.users || []),
    createUser: (data) => post('admin/users', data),
    updateUser: (id, data) => put(`admin/users/${id}`, data),
    deleteUser: (id) => del(`admin/users/${id}`),
    getAuditLogs: (params) => get('admin/audit', params).then(res => res?.logs || []),
    getRebootStatus: () => get('admin/reboot-status').then(res => res?.endpoints || []),
    getConnectors: () => get('admin/connectors').then(res => {
        const list = res?.connectors || res;
        return Array.isArray(list) ? list : [];
    }),
    getSystemErrors: () => get('admin/audit', { type: 'ERROR' }).then(res => res?.logs || []),
    getCredentials: () => get('admin/credentials').then(res => res?.credentials || []),
    saveCredentials: (type, username, password) => post('admin/credentials', { type, username, password }),
    testCredentials: (type) => post('admin/credentials/test', { type }),
    getEnvironmentConfig: () => get('admin/environment').then(res => res?.config || []),
    saveEnvironmentConfig: (key, value, description) => post('admin/environment', { key, value, description }),
};

export const performanceService = {
    getPerformanceReport: (hostname, period = '7d') => get('performance/report', { hostname, period }),
    getResourceUtilization: (hostname, metric, period = '24h') => get('performance/utilization', { hostname, metric, period }),
    getPerformanceAlerts: (params) => get('performance/alerts', params),
};

export const computerService = {
    getAll: (params) => get('computers', params).then(res => res?.computers || res || []),
    getByName: (name) => get(`computers/${encodeURIComponent(name)}`),
};

export const inventoryService = {
    getAll:         (params) => get('inventory', params).then(res => res?.inventory || res || []),
    getByHostname:  (hostname) => get(`inventory/${hostname}`),
    getLifecycle:   () => get('inventory/lifecycle'),
    exportCSV:      (params) => get('inventory/export', params),
};

export const historicalService = {
    getHeatmap:     (params) => get('historical/heatmap', params),
    getTimeline:    (computer) => get(`historical/timeline/${computer}`),
    getComparison:  (computers, period) => post('historical/compare', { computers, period }),
    getDriftAnalysis: () => get('historical/drift'),
    getCutoverReport: (params) => get('historical/cutover', params),
};

export const errorLogService = {
    logFrontendError: async (message, stack, url) => {
        try {
            await post('audit/frontend-error', { message, stack, url, userAgent: navigator.userAgent });
        } catch { /* silent */ }
    }
};

export { apiClient };
export default apiClient;
