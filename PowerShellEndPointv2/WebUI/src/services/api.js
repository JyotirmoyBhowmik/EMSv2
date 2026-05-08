import axios from 'axios';

// ── Auto-detect API URL ─────────────────────────────
const API_BASE_URL = 
    process.env.REACT_APP_API_URL ||
    (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
        ? 'http://localhost:5000'
        : (window.location.port === '3000' 
            ? `http://${window.location.hostname}:5000` 
            : window.location.origin + '/api'));

// ── Axios Instance ──────────────────────────────────
const apiClient = axios.create({
    baseURL: API_BASE_URL,
    timeout: 60000,               // 60s — scans can take time
    headers: { 'Content-Type': 'application/json' }
});

// ── Request Interceptor ─────────────────────────────
apiClient.interceptors.request.use((config) => {
    const token = localStorage.getItem('auth_token') || localStorage.getItem('token');
    const expiry = localStorage.getItem('auth_token_expiry');
    
    // Auth Token
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }

    // Custom EMS Headers for Auditing
    try {
        const user = JSON.parse(localStorage.getItem('user') || 'null');
        if (user?.username) config.headers['X-EMS-Username'] = user.username;
        if (user?.role)     config.headers['X-EMS-Role']     = user.role;
        if (Array.isArray(user?.groups) && user.groups.length > 0) {
            config.headers['X-EMS-Groups'] = user.groups.join(';');
        }
    } catch { /* ignore parse errors */ }

    // Expiry Check
    if (token && expiry && Date.now() > parseInt(expiry, 10)) {
        localStorage.clear();
        if (window.location.pathname !== '/login') {
            window.location.href = '/login';
        }
        return Promise.reject(new Error('Session expired'));
    }
    
    return config;
});

// ── Response Interceptor ────────────────────────────
apiClient.interceptors.response.use(
    (response) => response,
    async (error) => {
        const config = error.config;

        // 401 → force re-login
        if (error.response?.status === 401) {
            localStorage.clear();
            if (window.location.pathname !== '/login') {
                window.location.href = '/login';
            }
            return Promise.reject(error);
        }
        
        // Network errors → retry with backoff (up to 3 times)
        if (!error.response && (!config._retryCount || config._retryCount < 3)) {
            config._retryCount = (config._retryCount || 0) + 1;
            const backoff = Math.pow(2, config._retryCount) * 1000;
            await new Promise(r => setTimeout(r, backoff));
            return apiClient(config);
        }

        // Friendly error messages
        if (!error.response) {
            error.friendlyMessage = error.code === 'ECONNABORTED'
                ? 'Request timed out. The server took too long to respond.'
                : `Cannot reach the API server at ${API_BASE_URL}. Verify the server is running.`;
        } else {
            const msg = error.response.data?.message || error.response.data?.error;
            if (msg) error.friendlyMessage = msg;
        }
        
        return Promise.reject(error);
    }
);

// ── Helper Methods ──────────────────────────────────
const get = (url, params) => apiClient.get(url, { params }).then(r => r.data);
const post = (url, data, config = {}) => apiClient.post(url, data, config).then(r => r.data);
const put = (url, data) => apiClient.put(url, data).then(r => r.data);
const del = (url) => apiClient.delete(url).then(r => r.data);

// ── Auth Service ────────────────────────────────────
export const authService = {
    login: (username, password, provider = 'Standalone') => 
        post('/auth/login', { username, password, provider }).then(data => {
            if (data.success && data.user) {
                localStorage.setItem('auth_token', data.token || '');
                localStorage.setItem('user', JSON.stringify(data.user));
                localStorage.setItem('auth_token_expiry', 
                    Date.now() + (data.expiresIn || 86400) * 1000
                );
            }
            return data;
        }),
    logout: () => {
        localStorage.clear();
        window.location.href = '/login';
    },
    getProviders: () => get('/auth/providers'),
    validate: () => get('/auth/validate'),
};

// ── Scan Service (extended timeouts) ────────────────
export const scanService = {
    scanSingle:     (target, protocol) => post('/scan/single', { target, protocol }, { timeout: 120000 }),
    scanBulk:       (targets, protocol) => post('/scan/bulk', { targets, protocol }, { timeout: 300000 }),
    getScanStatus:  (scanId) => get('/scan/status', { scanId }),
    getScanResult:  (scanId) => get('/scan/result', { scanId }),
    getScanTrace:   (scanId) => get('/scan/trace',  { scanId }),
    archiveScan:    (scanId, reason) => post(`/results/${scanId}/archive`, { reason }),
    restoreScan:    (scanId) => post(`/results/${scanId}/restore`, {}),
};

// ── Dashboard Service ───────────────────────────────
export const dashboardService = {
    getStats: (range) => get('/api/dashboard/stats', { range }),
    getSummary: () => get('/dashboard/summary'),
    getTopIssues: () => get('/dashboard/top-issues'),
};

// ── Results & History Service ───────────────────────
export const resultsService = {
    getAll: (params) => get('/results', params),
    getById: (id) => get(`/results/${id}`),
    getLatest: () => get('/results/latest'),
};

// ── Compliance Service ──────────────────────────────
export const complianceService = {
    getReport: (params) => get('/compliance/report', params),
    getHistory: (params) => get('/compliance/history', params),
};

// ── Computer Service ───────────────────────────────
export const computerService = {
    getAll: (params) => get('/computers', params),
    getByName: (name) => get(`/computers/${encodeURIComponent(name)}`),
};

// ── Admin Service ───────────────────────────────────
export const adminService = {
    getSettings: () => get('/admin/settings'),
    updateSetting: (key, enabled) => put(`/admin/settings/${key}`, { enabled }),
    getUsers: () => get('/admin/users'),
    createUser: (data) => post('/admin/users', data),
    updateUser: (id, data) => put(`/admin/users/${id}`, data),
    deleteUser: (id) => del(`/admin/users/${id}`),
    getAuditLogs: (params) => get('/admin/audit', params),
    getRebootStatus: () => get('/admin/reboot-status'),
    getConnectors: () => get('/admin/connectors'),
};

export { apiClient };
export default apiClient;
