-- EMS Granular Metrics Database Schema
-- Version: 2.1 (Enhancement)
-- Description: 60+ dedicated tables for each monitoring parameter
-- Primary Key: computer_name for all metric tables

-- ===================================
-- CORE TABLES
-- ===================================

-- Central computer registry
CREATE TABLE computers (
    computer_name VARCHAR(255) PRIMARY KEY,
    ip_address INET,
    mac_address VARCHAR(17),
    operating_system VARCHAR(100),
    os_version VARCHAR(50),
    os_build VARCHAR(50),
    domain VARCHAR(100),
    is_domain_joined BOOLEAN DEFAULT true,
    computer_type VARCHAR(50) CHECK (computer_type IN ('Desktop', 'Laptop', 'Server', 'Workstation')),
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    serial_number VARCHAR(100),
    location VARCHAR(100),
    department VARCHAR(100),
    asset_tag VARCHAR(100),
    first_seen TIMESTAMP DEFAULT NOW(),
    last_seen TIMESTAMP DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_computers_domain ON computers(domain);
CREATE INDEX idx_computers_active ON computers(is_active);
CREATE INDEX idx_computers_type ON computers(computer_type);
CREATE INDEX idx_computers_last_seen ON computers(last_seen DESC);
CREATE INDEX idx_computers_ip ON computers(ip_address);

-- Computer to AD User mapping (many-to-many)
CREATE TABLE computer_ad_users (
    id SERIAL PRIMARY KEY,
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL,
    user_sid VARCHAR(255),
    user_display_name VARCHAR(255),
    user_email VARCHAR(255),
    user_department VARCHAR(100),
    is_primary_user BOOLEAN DEFAULT false,
    last_login TIMESTAMP,
    login_count INTEGER DEFAULT 0,
    first_seen TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(computer_name, user_id)
);

CREATE INDEX idx_computer_users_computer ON computer_ad_users(computer_name);
CREATE INDEX idx_computer_users_user ON computer_ad_users(user_id);
CREATE INDEX idx_computer_users_primary ON computer_ad_users(is_primary_user);

-- ===================================
-- SYSTEM HEALTH METRICS (10 tables)
-- ===================================

-- 1. CPU Usage
CREATE TABLE metric_cpu_usage (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    usage_percent DECIMAL(5,2),
    core_count INTEGER,
    logical_processors INTEGER,
    processor_name VARCHAR(255),
    processor_speed_mhz INTEGER,
    l2_cache_kb INTEGER,
    l3_cache_mb INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);
CREATE INDEX idx_cpu_timestamp ON metric_cpu_usage(timestamp DESC);
CREATE INDEX idx_cpu_usage ON metric_cpu_usage(usage_percent);

-- 2. Memory Usage
CREATE TABLE metric_memory (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    total_gb DECIMAL(10,2),
    available_gb DECIMAL(10,2),
    used_gb DECIMAL(10,2),
    usage_percent DECIMAL(5,2),
    committed_gb DECIMAL(10,2),
    page_file_total_gb DECIMAL(10,2),
    page_file_usage_percent DECIMAL(5,2),
    memory_speed_mhz INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);
CREATE INDEX idx_memory_timestamp ON metric_memory(timestamp DESC);
CREATE INDEX idx_memory_usage ON metric_memory(usage_percent);

-- 3. Disk Space (per drive)
CREATE TABLE metric_disk_space (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    drive_letter CHAR(1),
    volume_name VARCHAR(255),
    total_gb DECIMAL(10,2),
    free_gb DECIMAL(10,2),
    used_gb DECIMAL(10,2),
    usage_percent DECIMAL(5,2),
    file_system VARCHAR(20),
    drive_type VARCHAR(50),
    is_system_drive BOOLEAN DEFAULT false,
    PRIMARY KEY (computer_name, timestamp, drive_letter)
);
CREATE INDEX idx_disk_timestamp ON metric_disk_space(timestamp DESC);
CREATE INDEX idx_disk_usage ON metric_disk_space(usage_percent);

-- 4. Disk Performance
CREATE TABLE metric_disk_performance (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    disk_index INTEGER,
    disk_name VARCHAR(255),
    read_speed_mbps DECIMAL(10,2),
    write_speed_mbps DECIMAL(10,2),
    average_response_time_ms DECIMAL(10,3),
    queue_length INTEGER,
    disk_health VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp, disk_index)
);

-- 5. Network Adapters
CREATE TABLE metric_network_adapters (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    adapter_name VARCHAR(255),
    mac_address VARCHAR(17),
    ip_addresses TEXT[], -- Array of IPs
    adapter_status VARCHAR(50),
    link_speed_mbps INTEGER,
    duplex_mode VARCHAR(20),
    dhcp_enabled BOOLEAN,
    dns_servers TEXT[],
    is_wireless BOOLEAN DEFAULT false,
    PRIMARY KEY (computer_name, timestamp, adapter_name)
);

-- 6. Temperature Sensors
CREATE TABLE metric_temperature (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    sensor_name VARCHAR(255),
    temperature_celsius DECIMAL(5,2),
    sensor_type VARCHAR(50), -- CPU, GPU, HDD, Motherboard
    threshold_warning DECIMAL(5,2),
    threshold_critical DECIMAL(5,2),
    PRIMARY KEY (computer_name, timestamp, sensor_name)
);

-- 7. Power Status
CREATE TABLE metric_power_status (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    power_source VARCHAR(50), -- AC, Battery, UPS
    battery_present BOOLEAN,
    battery_percent INTEGER,
    battery_status VARCHAR(50),
    estimated_runtime_minutes INTEGER,
    power_plan VARCHAR(100),
    PRIMARY KEY (computer_name, timestamp)
);

-- 8. BIOS Information
CREATE TABLE metric_bios_info (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    bios_version VARCHAR(100),
    bios_manufacturer VARCHAR(100),
    bios_release_date DATE,
    smbios_version VARCHAR(50),
    uefi_mode BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

-- 9. Motherboard
CREATE TABLE metric_motherboard (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    serial_number VARCHAR(100),
    version VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp)
);

-- 10. System Uptime
CREATE TABLE metric_system_uptime (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    last_boot_time TIMESTAMP,
    uptime_days INTEGER,
    uptime_hours INTEGER,
    uptime_minutes INTEGER,
    total_uptime_minutes INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);

-- ===================================
-- SECURITY METRICS (15 tables)
-- ===================================

-- 11. Windows Updates
CREATE TABLE metric_windows_updates (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    total_updates INTEGER,
    pending_updates INTEGER,
    failed_updates INTEGER,
    hidden_updates INTEGER,
    last_update_date TIMESTAMP,
    last_check_date TIMESTAMP,
    auto_update_enabled BOOLEAN,
    reboot_required BOOLEAN,
    update_service VARCHAR(50), -- WSUS, Windows Update, SCCM
    PRIMARY KEY (computer_name, timestamp)
);

-- 12. Antivirus Status
CREATE TABLE metric_antivirus (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    av_product VARCHAR(255),
    av_vendor VARCHAR(100),
    av_version VARCHAR(100),
    definitions_version VARCHAR(100),
    definitions_date DATE,
    definitions_age_days INTEGER,
    real_time_protection BOOLEAN,
    last_scan_date TIMESTAMP,
    last_scan_type VARCHAR(50),
    threat_count INTEGER,
    quarantine_count INTEGER,
    av_enabled BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

-- 13. Firewall Status
CREATE TABLE metric_firewall (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    domain_profile_enabled BOOLEAN,
    private_profile_enabled BOOLEAN,
    public_profile_enabled BOOLEAN,
    active_profile VARCHAR(50),
    inbound_default_action VARCHAR(20),
    outbound_default_action VARCHAR(20),
    firewall_product VARCHAR(100),
    total_rules INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);

-- 14. Local User Accounts
CREATE TABLE metric_user_accounts (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    total_users INTEGER,
    enabled_users INTEGER,
    disabled_users INTEGER,
    admin_users INTEGER,
    guest_enabled BOOLEAN,
    password_never_expires_count INTEGER,
    inactive_users_30days INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);

-- 15. Local Group Membership
CREATE TABLE metric_group_membership (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    group_name VARCHAR(255),
    member_count INTEGER,
    members TEXT[], -- Array of usernames
    is_builtin BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, group_name)
);

-- 16. Login History (Last 10 logins)
CREATE TABLE metric_login_history (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    login_time TIMESTAMP,
    logout_time TIMESTAMP,
    user_name VARCHAR(255),
    login_type VARCHAR(50), -- Interactive, Remote, Network
    source_ip INET,
    session_duration_minutes INTEGER,
    PRIMARY KEY (computer_name, timestamp, login_time, user_name)
);

-- 17. Failed Login Attempts
CREATE TABLE metric_failed_logins (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    failed_count_24h INTEGER,
    failed_count_7d INTEGER,
    last_failed_user VARCHAR(255),
    last_failed_time TIMESTAMP,
    lockout_threshold INTEGER,
    account_lockout_enabled BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

-- 18. BitLocker Status
CREATE TABLE metric_bitlocker (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    drive_letter CHAR(1),
    protection_status VARCHAR(50),
    encryption_percentage DECIMAL(5,2),
    encryption_method VARCHAR(50),
    key_protectors TEXT[],
    conversion_status VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp, drive_letter)
);

-- 19. TPM Status
CREATE TABLE metric_tpm (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    tpm_present BOOLEAN,
    tpm_ready BOOLEAN,
    tpm_enabled BOOLEAN,
    tpm_activated BOOLEAN,
    tpm_version VARCHAR(20),
    manufacturer_version VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp)
);

-- 20. Secure Boot
CREATE TABLE metric_secure_boot (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    secure_boot_enabled BOOLEAN,
    secure_boot_state VARCHAR(50),
    platform_key_enrolled BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

-- 21. Audit Policies
CREATE TABLE metric_audit_policies (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    policy_category VARCHAR(255),
    subcategory VARCHAR(255),
    success_enabled BOOLEAN,
    failure_enabled BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, policy_category, subcategory)
);

-- 22. Password Policy
CREATE TABLE metric_password_policy (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    min_password_length INTEGER,
    password_history_count INTEGER,
    max_password_age_days INTEGER,
    min_password_age_days INTEGER,
    complexity_enabled BOOLEAN,
    reversible_encryption BOOLEAN,
    lockout_threshold INTEGER,
    lockout_duration_minutes INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);

-- 23. SMB Shares
CREATE TABLE metric_smb_shares (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    share_name VARCHAR(255),
    share_path VARCHAR(500),
    description TEXT,
    max_connections INTEGER,
    current_connections INTEGER,
    permissions TEXT[],
    is_hidden BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, share_name)
);

-- 24. Open Ports
CREATE TABLE metric_open_ports (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    port_number INTEGER,
    protocol VARCHAR(10),
    state VARCHAR(50),
    process_name VARCHAR(255),
    process_id INTEGER,
    local_address VARCHAR(50),
    is_listening BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, port_number, protocol)
);

-- 25. Certificates
CREATE TABLE metric_certificates (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    thumbprint VARCHAR(100),
    subject VARCHAR(500),
    issuer VARCHAR(500),
    not_before DATE,
    not_after DATE,
    days_until_expiry INTEGER,
    has_private_key BOOLEAN,
    key_length INTEGER,
    store_location VARCHAR(100),
    is_expired BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, thumbprint)
);

-- ===================================
-- NETWORK METRICS (8 tables)
-- ===================================

-- 26. Active Network Connections
CREATE TABLE metric_network_connections (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    connection_id SERIAL,
    protocol VARCHAR(10),
    local_address INET,
    local_port INTEGER,
    remote_address INET,
    remote_port INTEGER,
    state VARCHAR(50),
    process_name VARCHAR(255),
    process_id INTEGER,
    PRIMARY KEY (computer_name, timestamp, connection_id)
);

-- 27. Network Statistics
CREATE TABLE metric_network_stats (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    adapter_name VARCHAR(255),
    bytes_sent_mb DECIMAL(15,2),
    bytes_received_mb DECIMAL(15,2),
    packets_sent BIGINT,
    packets_received BIGINT,
    errors_inbound INTEGER,
    errors_outbound INTEGER,
    PRIMARY KEY (computer_name, timestamp, adapter_name)
);

-- 28. DNS Cache
CREATE TABLE metric_dns_cache (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    record_name VARCHAR(500),
    record_type VARCHAR(20),
    record_data VARCHAR(500),
    ttl INTEGER,
    PRIMARY KEY (computer_name, timestamp, record_name, record_type)
);

-- 29. Routing Table
CREATE TABLE metric_routing_table (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    destination CIDR,
    gateway INET,
    interface_index INTEGER,
    interface_name VARCHAR(255),
    metric INTEGER,
    is_persistent BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, destination)
);

-- 30. Network Speed Test
CREATE TABLE metric_network_speed (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    download_mbps DECIMAL(10,2),
    upload_mbps DECIMAL(10,2),
    latency_ms DECIMAL(10,2),
    jitter_ms DECIMAL(10,2),
    packet_loss_percent DECIMAL(5,2),
    test_server VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp)
);

-- 31. WiFi Networks (Available and connected)
CREATE TABLE metric_wifi_networks (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    ssid VARCHAR(255),
    signal_strength_percent INTEGER,
    channel INTEGER,
    frequency_ghz DECIMAL(3,1),
    security_type VARCHAR(50),
    is_connected BOOLEAN,
    PRIMARY KEY (computer_name, timestamp, ssid)
);

-- 32. VPN Connections
CREATE TABLE metric_vpn_connections (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    connection_name VARCHAR(255),
    connection_status VARCHAR(50),
    vpn_type VARCHAR(50),
    server_address VARCHAR(255),
    assigned_ip INET,
    connected_since TIMESTAMP,
    bytes_sent_mb DECIMAL(15,2),
    bytes_received_mb DECIMAL(15,2),
    PRIMARY KEY (computer_name, timestamp, connection_name)
);

-- 33. Proxy Settings
CREATE TABLE metric_proxy_settings (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    proxy_enabled BOOLEAN,
    proxy_server VARCHAR(255),
    proxy_port INTEGER,
    bypass_list TEXT[],
    auto_config_url VARCHAR(500),
    PRIMARY KEY (computer_name, timestamp)
);

-- Continue in next part (part 2)...
