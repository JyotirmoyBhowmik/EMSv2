import React, { useEffect, useMemo, useState } from 'react';
import { complianceService, resultsService } from '../services/api';
import { Link } from 'react-router-dom';

const toRows = (payload) => {
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload?.results)) return payload.results;
    if (Array.isArray(payload?.data)) return payload.data;
    return [];
};
const getLatestRowKey = (row) => {
    return String(
        row?.hostname ||
        row?.Hostname ||
        row?.computer_name ||
        row?.ComputerName ||
        row?.Computer_Name ||
        ''
    ).trim().toUpperCase();
};

const getLatestRowTime = (row) => {
    const value =
        row?.lastchecked ||
        row?.LastChecked ||
        row?.last_checked ||
        row?.scan_time ||
        row?.ScanTime ||
        row?.created_at ||
        row?.CreatedAt ||
        '';

    const parsed = new Date(value).getTime();
    return Number.isFinite(parsed) ? parsed : 0;
};

const dedupeLatestRows = (rows) => {
    if (!Array.isArray(rows)) return [];

    const latestByHost = new Map();
    const rowsWithoutHost = [];

    rows.forEach((row) => {
        const key = getLatestRowKey(row);

        if (!key) {
            rowsWithoutHost.push(row);
            return;
        }

        const existing = latestByHost.get(key);

        if (!existing || getLatestRowTime(row) >= getLatestRowTime(existing)) {
            latestByHost.set(key, row);
        }
    });

    return [...latestByHost.values(), ...rowsWithoutHost];
};

const text = (v) => {
    if (v === null || v === undefined || v === '') return '-';
    return String(v);
};

const isBlank = (v) => {
    const value = String(v ?? '').trim();
    return value === '' || value === '-' || value.toLowerCase() === 'null' || value.toLowerCase() === 'unknown';
};

const normalizeHost = (v) => String(v || '').trim().toLowerCase();

const pickAny = (row, names) => {
    if (!row) return '';

    for (const name of names) {
        if (Object.prototype.hasOwnProperty.call(row, name)) {
            const value = row[name];

            if (String(value ?? '').trim() !== '') {
                return value;
            }
        }
    }

    return '';
};

const firstNonBlank = (...values) => {
    for (const item of values) {
        const value = String(item ?? '').trim();

        if (value && value !== '-' && value.toLowerCase() !== 'null' && value.toLowerCase() !== 'undefined') {
            return item;
        }
    }

    return '';
};

const isCollectionFailedRow = (row) => {
    const combinedText = [
        row.collection_status,
        row.scan_status,
        row.inventory_status,
        row.compliance_issues,
        row.compliance_warnings,
        row.comments,
        row.error,
        row.error_message,
        row.message
    ].map((v) => String(v ?? '').toLowerCase()).join(' ');

    if (
        combinedText.includes('collection failed') ||
        combinedText.includes('inventory collection failed') ||
        combinedText.includes('rpc unavailable') ||
        combinedText.includes('rpc server') ||
        combinedText.includes('unreachable') ||
        combinedText.includes('access denied') ||
        combinedText.includes('wmi')
    ) {
        return true;
    }

    const missingInventoryFields = [
        row.manufacturer,
        row.model,
        row.domain_user,
        row.timesync_with_ntp,
        row.readonly_usb,
        row.screensaver_policy,
        row.restrict_software_installation_policy
    ].filter(isBlank).length;

    return missingInventoryFields >= 5;
};

const enrichRowsFromRawResults = async (rows) => {
    if (!resultsService?.getResults || !Array.isArray(rows) || rows.length === 0) {
        return rows;
    }

    try {
        const rawPayload = await resultsService.getResults();
        const rawRows = toRows(rawPayload);
        const latestByHost = new Map();

        rawRows.forEach((raw) => {
            const key = normalizeHost(raw.hostname || raw.Hostname || raw.computer_name || raw.ComputerName || raw.Computer_Name);

            if (!key) return;

            const current = latestByHost.get(key);
            const rawTime = new Date(raw.lastchecked || raw.LastChecked || raw.last_checked || raw.scan_time || raw.ScanTime || 0).getTime();
            const currentTime = current
                ? new Date(current.lastchecked || current.LastChecked || current.last_checked || current.scan_time || current.ScanTime || 0).getTime()
                : -1;

            if (!current || rawTime >= currentTime) {
                latestByHost.set(key, raw);
            }
        });

        return rows.map((row) => {
            const key = normalizeHost(row.hostname || row.Hostname || row.computer_name || row.ComputerName || row.Computer_Name);
            const raw = latestByHost.get(key);

            if (!raw) return row;

            return {
                ...row,
                all_security_kbs: firstNonBlank(row.all_security_kbs, pickAny(raw, ['all_security_kbs', 'AllSecurityKBs', 'All_Security_KBs', 'All Security KBs', 'security_kbs', 'SecurityKBs', 'installed_kbs', 'InstalledKBs'])),
                all_security_kbs_installedon: firstNonBlank(row.all_security_kbs_installedon, pickAny(raw, ['all_security_kbs_installedon', 'AllSecurityKBsInstalledOn', 'All_Security_KBs_InstalledOn', 'All Security KBs InstalledOn', 'security_kbs_installedon', 'SecurityKBsInstalledOn', 'installed_kbs_installedon', 'InstalledKBsInstalledOn'])),
                os_edition: firstNonBlank(row.os_edition, pickAny(raw, ['os_edition', 'OS_Edition', 'OSEdition', 'OS Edition', 'edition'])),
                os_version: firstNonBlank(row.os_version, pickAny(raw, ['os_version', 'OS_Version', 'OSVersion', 'OS Version', 'version'])),
                os_build: firstNonBlank(row.os_build, pickAny(raw, ['os_build', 'OS_Build', 'OSBuild', 'OS Build', 'build'])),
                symantec_management_agent: firstNonBlank(row.symantec_management_agent, pickAny(raw, ['symantec_management_agent', 'Symantec_Management_Agent', 'SymantecManagementAgent', 'Symantec Management Agent', 'sma_status', 'SMAStatus', 'altiris_agent', 'AltirisAgent']))
            };
        });
    } catch {
        return rows;
    }
};

const csvEscape = (value) => {
    const s = String(value ?? '');
    if (s.includes('"') || s.includes(',') || s.includes('\n') || s.includes('\r')) {
        return `"${s.replace(/"/g, '""')}"`;
    }
    return s;
};

const ComplianceReport = () => {
    const [rows, setRows] = useState([]);
    const [search, setSearch] = useState('');
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');

    const columns = [
        { key: 'status', label: 'Status' },
        { key: 'hostname', label: 'Hostname' },
        { key: 'computer_name', label: 'ComputerName' },
        { key: 'manufacturer', label: 'Manufacturer' },
        { key: 'model', label: 'Model' },
        { key: 'domain_user', label: 'DomainUser' },
        { key: 'poweron_password', label: 'Poweron Password' },
        { key: 'admin_password', label: 'Admin Password' },
        { key: 'timesync_with_ntp', label: 'Time Sync With NTP' },
        { key: 'readonly_usb', label: 'Read Only USB' },
        { key: 'screensaver_policy', label: 'Screensaver' },
        { key: 'restrict_software_installation_policy', label: 'Restrict Software' },
        { key: 'all_security_kbs', label: 'All Security KBs' },
        { key: 'all_security_kbs_installedon', label: 'All Security KBs InstalledOn' },
        { key: 'os_edition', label: 'OS Edition' },
        { key: 'os_version', label: 'OS Version' },
        { key: 'os_build', label: 'OS Build' },
        { key: 'symantec_management_agent', label: 'Symantec Management Agent' },
        { key: 'compliance_issues', label: 'Compliance Issues' },
        { key: 'compliance_warnings', label: 'Compliance Warnings' },
        { key: 'comments', label: 'Comments' },
        { key: 'lastchecked', label: 'Last Checked' }
    ];

    const loadReport = async () => {
        setLoading(true);
        setError('');

        try {
            const compliantPayload = await complianceService.getCompliant();
            const partialPayload = await complianceService.getPartial();

            let compliantRows = toRows(compliantPayload).map((row) => ({
                ...row,
                status: 'Compliant'
            }));

            let partialRows = toRows(partialPayload).map((row) => ({
                ...row,
                status: isCollectionFailedRow(row) ? 'Collection Failed' : 'Partial Compliant'
            }));

            let combined = [...compliantRows, ...partialRows];
            combined = await enrichRowsFromRawResults(combined);

            setRows(dedupeLatestRows(combined));
        } catch (err) {
            setError(err?.response?.data?.message || err?.message || 'Failed to load compliance report');
            setRows([]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        loadReport();
    }, []);

    const filteredRows = useMemo(() => {
        const term = search.trim().toLowerCase();

        if (!term) return rows;

        return rows.filter((row) =>
            Object.values(row || {}).some((value) =>
                String(value ?? '').toLowerCase().includes(term)
            )
        );
    }, [rows, search]);

    const counts = useMemo(() => {
        return {
            total: rows.length,
            compliant: rows.filter((row) => row.status === 'Compliant').length,
            partial: rows.filter((row) => row.status === 'Partial Compliant').length,
            collectionFailed: rows.filter((row) => row.status === 'Collection Failed').length
        };
    }, [rows]);

    const exportCsv = () => {
        const header = columns.map((column) => csvEscape(column.label)).join(',');
        const body = filteredRows.map((row) =>
            columns.map((column) => csvEscape(row[column.key])).join(',')
        );

        const csv = [header, ...body].join('\r\n');
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');

        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');

        link.href = url;
        link.download = `EMS_Compliance_Report_${timestamp}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    };
    return (
        <div>
            <h1>Compliance Report</h1>

            <div className="stat-cards">
                <div className="stat-card">
                    <div className="stat-label">Total Hosts</div>
                    <div className="stat-value">{counts.total}</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label">Compliant</div>
                    <div className="stat-value">{counts.compliant}</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label">Partial Compliant</div>
                    <div className="stat-value">{counts.partial}</div>
                </div>
                <div className="stat-card">
                    <div className="stat-label">Collection Failed</div>
                    <div className="stat-value">{counts.collectionFailed}</div>
                </div>
            </div>

            <div className="card" style={{ display: 'flex', gap: '12px', alignItems: 'center', flexWrap: 'wrap' }}>
                <button className="btn btn-primary" onClick={exportCsv} disabled={filteredRows.length === 0}>
                    Export CSV
                </button>
                <button className="btn" onClick={loadReport} disabled={loading}>
                    Refresh
                </button>
                <span>Showing {filteredRows.length} of {rows.length} host(s)</span>
            </div>

            <input
                className="form-control"
                placeholder="Search..."
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                style={{ marginBottom: '12px' }}
            />

            {loading && <div className="card">Loading compliance report...</div>}

            {!loading && error && (
                <div className="card" style={{ color: '#721c24', background: '#f8d7da' }}>
                    {error}
                </div>
            )}

            {!loading && !error && (
                <div className="table-container">
                    <table>
                        <thead>
                            <tr>
                                {columns.map((column) => (
                                    <th key={column.key}>{column.label}</th>
                                ))}
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {filteredRows.length === 0 ? (
                                <tr>
                                    <td colSpan={columns.length} style={{ textAlign: 'center', padding: '20px' }}>
                                        No records found
                                    </td>
                                </tr>
                            ) : (
                                filteredRows.map((row, index) => (
                                    <tr key={`${row.hostname || row.computer_name || 'row'}-${index}`}>
                                        {columns.map((column) => (
                                            <td key={column.key}>{text(row[column.key])}</td>
                                        ))}
                                        <td>
                                            {row.scan_id ? <Link to={`/scan/trace/${row.scan_id}`} className="btn btn-sm" style={{ padding: '2px 8px', fontSize: '0.75rem' }}>View Trace</Link> : '-'}
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
};

export default ComplianceReport;

