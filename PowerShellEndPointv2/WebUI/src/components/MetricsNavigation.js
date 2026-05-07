import React from 'react';
import { Link } from 'react-router-dom';

function MetricsNavigation() {
    const metrics = [
        {
            category: 'System Health',
            items: [
                { name: 'CPU Usage', path: '/metrics/cpu', icon: '🖥️' },
                { name: 'Memory Usage', path: '/metrics/memory', icon: '💾' },
                { name: 'Disk Space', path: '/metrics/disk', icon: '💿' },
                { name: 'Disk Performance', path: '/metrics/disk_performance', icon: '⚡' },
                { name: 'Network Adapters', path: '/metrics/network_adapters', icon: '🌐' },
                { name: 'Temperature', path: '/metrics/temperature', icon: '🌡️' },
                { name: 'Power Status', path: '/metrics/power', icon: '🔋' },
                { name: 'BIOS Info', path: '/metrics/bios', icon: '⚙️' },
                { name: 'Motherboard', path: '/metrics/motherboard', icon: '🎛️' },
                { name: 'System Uptime', path: '/metrics/uptime', icon: '⏱️' }
            ]
        },
        {
            category: 'Security',
            items: [
                { name: 'Windows Updates', path: '/metrics/windows_updates', icon: '🔄' },
                { name: 'Antivirus', path: '/metrics/antivirus', icon: '🛡️' },
                { name: 'Firewall', path: '/metrics/firewall', icon: '🔥' },
                { name: 'User Accounts', path: '/metrics/user_accounts', icon: '👤' },
                { name: 'Group Membership', path: '/metrics/groups', icon: '👥' },
                { name: 'Login History', path: '/metrics/login_history', icon: '📊' },
                { name: 'Failed Logins', path: '/metrics/failed_logins', icon: '🚫' },
                { name: 'BitLocker', path: '/metrics/bitlocker', icon: '🔒' },
                { name: 'TPM Status', path: '/metrics/tpm', icon: '🔐' },
                { name: 'Secure Boot', path: '/metrics/secure_boot', icon: '✅' },
                { name: 'Audit Policies', path: '/metrics/audit_policies', icon: '📋' },
                { name: 'Password Policy', path: '/metrics/password_policy', icon: '🔑' },
                { name: 'SMB Shares', path: '/metrics/smb_shares', icon: '📁' },
                { name: 'Open Ports', path: '/metrics/open_ports', icon: '🚪' },
                { name: 'Certificates', path: '/metrics/certificates', icon: '📜' }
            ]
        },
        {
            category: 'Network',
            items: [
                { name: 'Network Connections', path: '/metrics/network_connections', icon: '🔗' },
                { name: 'Network Statistics', path: '/metrics/network_stats', icon: '📈' },
                { name: 'DNS Cache', path: '/metrics/dns_cache', icon: '🗂️' },
                { name: 'Routing Table', path: '/metrics/routing', icon: '🗺️' },
                { name: 'Network Speed', path: '/metrics/network_speed', icon: '🚀' },
                { name: 'WiFi Networks', path: '/metrics/wifi', icon: '📡' },
                { name: 'VPN Connections', path: '/metrics/vpn', icon: '🔐' },
                { name: 'Proxy Settings', path: '/metrics/proxy', icon: '🌍' }
            ]
        },
        {
            category: 'Software & Compliance',
            items: [
                { name: 'Installed Software', path: '/metrics/software', icon: '📦' },
                { name: 'Startup Programs', path: '/metrics/startup', icon: '🚀' },
                { name: 'Windows Services', path: '/metrics/services', icon: '⚙️' },
                { name: 'Scheduled Tasks', path: '/metrics/tasks', icon: '📅' },
                { name: 'Browser Extensions', path: '/metrics/browser_extensions', icon: '🧩' },
                { name: 'Office Version', path: '/metrics/office', icon: '📊' },
                { name: 'Registry Settings', path: '/metrics/registry', icon: '📝' },
                { name: 'Group Policies', path: '/metrics/gpo', icon: '📜' },
                { name: 'Environment Variables', path: '/metrics/env_vars', icon: '🔧' },
                { name: 'Device Drivers', path: '/metrics/drivers', icon: '🔌' },
                { name: 'Windows Features', path: '/metrics/features', icon: '✨' },
                { name: 'PowerShell Version', path: '/metrics/powershell', icon: '💻' }
            ]
        },
        {
            category: 'User Experience',
            items: [
                { name: 'Login Time', path: '/metrics/login_time', icon: '⏱️' },
                { name: 'Application Crashes', path: '/metrics/crashes', icon: '💥' },
                { name: 'Browser Performance', path: '/metrics/browser_performance', icon: '🌐' },
                { name: 'Printing Issues', path: '/metrics/printing', icon: '🖨️' },
                { name: 'Mapped Drives', path: '/metrics/mapped_drives', icon: '🗂️' },
                { name: 'Installed Printers', path: '/metrics/printers', icon: '🖨️' },
                { name: 'Display Settings', path: '/metrics/display', icon: '🖥️' },
                { name: 'Sound Devices', path: '/metrics/sound', icon: '🔊' },
                { name: 'USB Devices', path: '/metrics/usb', icon: '🔌' },
                { name: 'Bluetooth Devices', path: '/metrics/bluetooth', icon: '📶' }
            ]
        },
        {
            category: 'Event Logs',
            items: [
                { name: 'System Events', path: '/metrics/system_events', icon: '📋' },
                { name: 'Application Events', path: '/metrics/app_events', icon: '📱' },
                { name: 'Security Events', path: '/metrics/security_events', icon: '🔒' },
                { name: 'Error Summary', path: '/metrics/errors', icon: '❌' },
                { name: 'Warning Summary', path: '/metrics/warnings', icon: '⚠️' }
            ]
        },
        {
            category: 'Performance Baselines',
            items: [
                { name: 'Performance Baseline', path: '/metrics/baseline', icon: '📊' },
                { name: 'Health Score History', path: '/metrics/health_history', icon: '💚' },
                { name: 'Compliance Score', path: '/metrics/compliance', icon: '✅' }
            ]
        }
    ];

    return (
        <div className="page-container">
            <div className="page-header">
                <h1>Metrics Explorer</h1>
                <p>Browse all {metrics.reduce((sum, cat) => sum + cat.items.length, 0)} available metrics</p>
            </div>

            {metrics.map((category) => (
                <div key={category.category} className="card" style={{ marginBottom: '20px' }}>
                    <h2>{category.category} ({category.items.length})</h2>
                    <div className="metrics-grid">
                        {category.items.map((metric) => (
                            <Link
                                key={metric.path}
                                to={metric.path}
                                className="metric-card"
                                style={{
                                    textDecoration: 'none',
                                    padding: '15px',
                                    border: '1px solid #ddd',
                                    borderRadius: '8px',
                                    display: 'flex',
                                    alignItems: 'center',
                                    gap: '10px',
                                    transition: 'all 0.2s',
                                    background: '#fff'
                                }}
                                onMouseEnter={(e) => {
                                    e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.1)';
                                    e.currentTarget.style.transform = 'translateY(-2px)';
                                }}
                                onMouseLeave={(e) => {
                                    e.currentTarget.style.boxShadow = 'none';
                                    e.currentTarget.style.transform = 'translateY(0)';
                                }}
                            >
                                <span style={{ fontSize: '24px' }}>{metric.icon}</span>
                                <span style={{ color: '#333', fontWeight: '500' }}>{metric.name}</span>
                            </Link>
                        ))}
                    </div>
                </div>
            ))}
        </div>
    );
}

export default MetricsNavigation;
