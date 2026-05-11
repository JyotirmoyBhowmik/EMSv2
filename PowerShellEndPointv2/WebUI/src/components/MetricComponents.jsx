import React, { useState, useEffect } from 'react';

// Reusable Metric Detail Component with filtering and export
function MetricDetail({ metricName, metricType, apiEndpoint }) {
    const [data, setData] = useState([]);
    const [loading, setLoading] = useState(true);
    const [filters, setFilters] = useState({
        computerName: '',
        startDate: '',
        endDate: '',
        limit: 100
    });

    useEffect(() => {
        fetchData();
    }, [filters]);

    const fetchData = async () => {
        try {
            setLoading(true);
            const params = new URLSearchParams(filters).toString();
            const response = await fetch(`${apiEndpoint}?${params}`, {
                headers: {
                    'Authorization': `Bearer ${localStorage.getItem('token')}`
                }
            });
            const result = await response.json();
            setData(result.data || []);
        } catch (err) {
            console.error('Error fetching metric data:', err);
        } finally {
            setLoading(false);
        }
    };

    const exportCSV = () => {
        if (data.length === 0) return;

        const headers = Object.keys(data[0]);
        const csvContent = [
            headers.join(','),
            ...data.map(row => headers.map(h => JSON.stringify(row[h] || '')).join(','))
        ].join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${metricType}_${new Date().toISOString().split('T')[0]}.csv`;
        a.click();
    };

    if (loading) return <div className="loading">Loading {metricName}...</div>;

    return (
        <div className="page-container">
            <div className="page-header">
                <h1>{metricName}</h1>
                <button className="btn btn-primary" onClick={exportCSV}>📥 Export CSV</button>
            </div>

            <div className="card" style={{ marginBottom: '20px' }}>
                <h3>Filters</h3>
                <div className="form-row">
                    <div className="form-group">
                        <label>Computer Name</label>
                        <input type="text" value={filters.computerName} onChange={(e) => setFilters({ ...filters, computerName: e.target.value })} placeholder="Filter by computer name" />
                    </div>
                    <div className="form-group">
                        <label>Start Date</label>
                        <input type="date" value={filters.startDate} onChange={(e) => setFilters({ ...filters, startDate: e.target.value })} />
                    </div>
                    <div className="form-group">
                        <label>End Date</label>
                        <input type="date" value={filters.endDate} onChange={(e) => setFilters({ ...filters, endDate: e.target.value })} />
                    </div>
                    <div className="form-group">
                        <label>Limit</label>
                        <select value={filters.limit} onChange={(e) => setFilters({ ...filters, limit: e.target.value })}>
                            <option>50</option><option>100</option><option>500</option><option>1000</option>
                        </select>
                    </div>
                </div>
                <button className="btn" onClick={fetchData}>Apply Filters</button>
            </div>

            <div className="card">
                <p>Total Records: {data.length}</p>
                <div className="table-responsive">
                    <table className="data-table">
                        <thead>
                            <tr>{data.length > 0 && Object.keys(data[0]).map(key => (<th key={key}>{key.replace(/_/g, ' ').toUpperCase()}</th>))}</tr>
                        </thead>
                        <tbody>
                            {data.map((row, idx) => (
                                <tr key={idx}>
                                    {Object.values(row).map((val, i) => (<td key={i}>{val !== null && val !== undefined ? String(val) : 'N/A'}</td>))}
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
                {data.length === 0 && <div className="empty-state"><p>No data found for the selected filters</p></div>}
            </div>
        </div>
    );
}

// ALL 63 METRIC PAGES - System Health (10)
export const CPUUsageMetric = () => <MetricDetail metricName="CPU Usage" metricType="cpu_usage" apiEndpoint="/api/metrics/cpu_usage" />;
export const MemoryMetric = () => <MetricDetail metricName="Memory Usage" metricType="memory" apiEndpoint="/api/metrics/memory" />;
export const DiskSpaceMetric = () => <MetricDetail metricName="Disk Space" metricType="disk_space" apiEndpoint="/api/metrics/disk_space" />;
export const DiskPerformanceMetric = () => <MetricDetail metricName="Disk Performance" metricType="disk_performance" apiEndpoint="/api/metrics/disk_performance" />;
export const NetworkAdaptersMetric = () => <MetricDetail metricName="Network Adapters" metricType="network_adapters" apiEndpoint="/api/metrics/network_adapters" />;
export const TemperatureMetric = () => <MetricDetail metricName="Temperature" metricType="temperature" apiEndpoint="/api/metrics/temperature" />;
export const PowerStatusMetric = () => <MetricDetail metricName="Power Status" metricType="power_status" apiEndpoint="/api/metrics/power_status" />;
export const BiosInfoMetric = () => <MetricDetail metricName="BIOS Information" metricType="bios_info" apiEndpoint="/api/metrics/bios_info" />;
export const MotherboardMetric = () => <MetricDetail metricName="Motherboard" metricType="motherboard" apiEndpoint="/api/metrics/motherboard" />;
export const SystemUptimeMetric = () => <MetricDetail metricName="System Uptime" metricType="system_uptime" apiEndpoint="/api/metrics/system_uptime" />;

// Security (15)
export const WindowsUpdatesMetric = () => <MetricDetail metricName="Windows Updates" metricType="windows_updates" apiEndpoint="/api/metrics/windows_updates" />;
export const AntivirusMetric = () => <MetricDetail metricName="Antivirus Status" metricType="antivirus" apiEndpoint="/api/metrics/antivirus" />;
export const FirewallMetric = () => <MetricDetail metricName="Firewall Status" metricType="firewall" apiEndpoint="/api/metrics/firewall" />;
export const UserAccountsMetric = () => <MetricDetail metricName="User Accounts" metricType="user_accounts" apiEndpoint="/api/metrics/user_accounts" />;
export const GroupMembershipMetric = () => <MetricDetail metricName="Group Membership" metricType="group_membership" apiEndpoint="/api/metrics/group_membership" />;
export const LoginHistoryMetric = () => <MetricDetail metricName="Login History" metricType="login_history" apiEndpoint="/api/metrics/login_history" />;
export const FailedLoginsMetric = () => <MetricDetail metricName="Failed Logins" metricType="failed_logins" apiEndpoint="/api/metrics/failed_logins" />;
export const BitLockerMetric = () => <MetricDetail metricName="BitLocker Encryption" metricType="bitlocker" apiEndpoint="/api/metrics/bitlocker" />;
export const TPMMetric = () => <MetricDetail metricName="TPM Status" metricType="tpm" apiEndpoint="/api/metrics/tpm" />;
export const SecureBootMetric = () => <MetricDetail metricName="Secure Boot" metricType="secure_boot" apiEndpoint="/api/metrics/secure_boot" />;
export const AuditPoliciesMetric = () => <MetricDetail metricName="Audit Policies" metricType="audit_policies" apiEndpoint="/api/metrics/audit_policies" />;
export const PasswordPolicyMetric = () => <MetricDetail metricName="Password Policy" metricType="password_policy" apiEndpoint="/api/metrics/password_policy" />;
export const SMBSharesMetric = () => <MetricDetail metricName="SMB Shares" metricType="smb_shares" apiEndpoint="/api/metrics/smb_shares" />;
export const OpenPortsMetric = () => <MetricDetail metricName="Open Ports" metricType="open_ports" apiEndpoint="/api/metrics/open_ports" />;
export const CertificatesMetric = () => <MetricDetail metricName="Certificates" metricType="certificates" apiEndpoint="/api/metrics/certificates" />;

// Network (8)
export const NetworkConnectionsMetric = () => <MetricDetail metricName="Network Connections" metricType="network_connections" apiEndpoint="/api/metrics/network_connections" />;
export const NetworkStatsMetric = () => <MetricDetail metricName="Network Statistics" metricType="network_stats" apiEndpoint="/api/metrics/network_stats" />;
export const DNSCacheMetric = () => <MetricDetail metricName="DNS Cache" metricType="dns_cache" apiEndpoint="/api/metrics/dns_cache" />;
export const RoutingTableMetric = () => <MetricDetail metricName="Routing Table" metricType="routing_table" apiEndpoint="/api/metrics/routing_table" />;
export const NetworkSpeedMetric = () => <MetricDetail metricName="Network Speed" metricType="network_speed" apiEndpoint="/api/metrics/network_speed" />;
export const WiFiNetworksMetric = () => <MetricDetail metricName="WiFi Networks" metricType="wifi_networks" apiEndpoint="/api/metrics/wifi_networks" />;
export const VPNConnectionsMetric = () => <MetricDetail metricName="VPN Connections" metricType="vpn_connections" apiEndpoint="/api/metrics/vpn_connections" />;
export const ProxySettingsMetric = () => <MetricDetail metricName="Proxy Settings" metricType="proxy_settings" apiEndpoint="/api/metrics/proxy_settings" />;

// Software & Compliance (12)
export const InstalledSoftwareMetric = () => <MetricDetail metricName="Installed Software" metricType="installed_software" apiEndpoint="/api/metrics/installed_software" />;
export const StartupProgramsMetric = () => <MetricDetail metricName="Startup Programs" metricType="startup_programs" apiEndpoint="/api/metrics/startup_programs" />;
export const ServicesMetric = () => <MetricDetail metricName="Windows Services" metricType="services" apiEndpoint="/api/metrics/services" />;
export const ScheduledTasksMetric = () => <MetricDetail metricName="Scheduled Tasks" metricType="scheduled_tasks" apiEndpoint="/api/metrics/scheduled_tasks" />;
export const BrowserExtensionsMetric = () => <MetricDetail metricName="Browser Extensions" metricType="browser_extensions" apiEndpoint="/api/metrics/browser_extensions" />;
export const OfficeVersionMetric = () => <MetricDetail metricName="Office Version" metricType="office_version" apiEndpoint="/api/metrics/office_version" />;
export const RegistrySettingsMetric = () => <MetricDetail metricName="Registry Settings" metricType="registry_settings" apiEndpoint="/api/metrics/registry_settings" />;
export const GPOAppliedMetric = () => <MetricDetail metricName="Group Policies Applied" metricType="gpo_applied" apiEndpoint="/api/metrics/gpo_applied" />;
export const EnvironmentVariablesMetric = () => <MetricDetail metricName="Environment Variables" metricType="environment_variables" apiEndpoint="/api/metrics/environment_variables" />;
export const DriversMetric = () => <MetricDetail metricName="Device Drivers" metricType="drivers" apiEndpoint="/api/metrics/drivers" />;
export const WindowsFeaturesMetric = () => <MetricDetail metricName="Windows Features" metricType="windows_features" apiEndpoint="/api/metrics/windows_features" />;
export const PowerShellVersionMetric = () => <MetricDetail metricName="PowerShell Version" metricType="powershell_version" apiEndpoint="/api/metrics/powershell_version" />;

// User Experience (10)
export const LoginTimeMetric = () => <MetricDetail metricName="Login Time" metricType="login_time" apiEndpoint="/api/metrics/login_time" />;
export const ApplicationCrashesMetric = () => <MetricDetail metricName="Application Crashes" metricType="application_crashes" apiEndpoint="/api/metrics/application_crashes" />;
export const BrowserPerformanceMetric = () => <MetricDetail metricName="Browser Performance" metricType="browser_performance" apiEndpoint="/api/metrics/browser_performance" />;
export const PrintingIssuesMetric = () => <MetricDetail metricName="Printing Issues" metricType="printing_issues" apiEndpoint="/api/metrics/printing_issues" />;
export const MappedDrivesMetric = () => <MetricDetail metricName="Mapped Drives" metricType="mapped_drives" apiEndpoint="/api/metrics/mapped_drives" />;
export const PrintersMetric = () => <MetricDetail metricName="Installed Printers" metricType="printers" apiEndpoint="/api/metrics/printers" />;
export const DisplaySettingsMetric = () => <MetricDetail metricName="Display Settings" metricType="display_settings" apiEndpoint="/api/metrics/display_settings" />;
export const SoundDevicesMetric = () => <MetricDetail metricName="Sound Devices" metricType="sound_devices" apiEndpoint="/api/metrics/sound_devices" />;
export const USBDevicesMetric = () => <MetricDetail metricName="USB Devices" metricType="usb_devices" apiEndpoint="/api/metrics/usb_devices" />;
export const BluetoothDevicesMetric = () => <MetricDetail metricName="Bluetooth Devices" metricType="bluetooth_devices" apiEndpoint="/api/metrics/bluetooth_devices" />;

// Event Logs (5)
export const SystemEventsMetric = () => <MetricDetail metricName="System Events" metricType="system_events" apiEndpoint="/api/metrics/system_events" />;
export const ApplicationEventsMetric = () => <MetricDetail metricName="Application Events" metricType="application_events" apiEndpoint="/api/metrics/application_events" />;
export const SecurityEventsMetric = () => <MetricDetail metricName="Security Events" metricType="security_events" apiEndpoint="/api/metrics/security_events" />;
export const ErrorSummaryMetric = () => <MetricDetail metricName="Error Summary" metricType="error_summary" apiEndpoint="/api/metrics/error_summary" />;
export const WarningSummaryMetric = () => <MetricDetail metricName="Warning Summary" metricType="warning_summary" apiEndpoint="/api/metrics/warning_summary" />;

// Performance Baselines (3)
export const PerformanceBaselineMetric = () => <MetricDetail metricName="Performance Baseline" metricType="performance_baseline" apiEndpoint="/api/metrics/performance_baseline" />;
export const HealthScoreHistoryMetric = () => <MetricDetail metricName="Health Score History" metricType="health_score_history" apiEndpoint="/api/metrics/health_score_history" />;
export const ComplianceScoreMetric = () => <MetricDetail metricName="Compliance Score" metricType="compliance_score" apiEndpoint="/api/metrics/compliance_score" />;

export default MetricDetail;
