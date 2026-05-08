import React, { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { complianceService, scanService, resultsService } from '../services/api';
import ComplianceReport from './ComplianceReport';

const WARNING_THRESHOLD = 70;
const CRITICAL_THRESHOLD = 90;

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

const value = (v) => (v === null || v === undefined || v === '' ? '-' : String(v));
const csvEscape = (value) => {
    const text = String(value ?? '');
    if (text.includes('"') || text.includes(',') || text.includes('\n') || text.includes('\r')) {
        return `"${text.replace(/"/g, '""')}"`;
    }
    return text;
};

const isBlank = (v) => {
    const text = String(v ?? '').trim();
    return text === '' || text === '-' || text.toLowerCase() === 'null' || text.toLowerCase() === 'unknown';
};

const normalizeHostKey = (v) => String(v || '').trim().toLowerCase();

const getTargetName = (row) => String(row?.hostname || row?.Hostname || row?.computer_name || row?.ComputerName || '').trim();

const parsePercent = (v) => {
    if (v === null || v === undefined || v === '') return null;

    const text = String(v).replace('%', '').trim();
    const match = text.match(/-?\d+(\.\d+)?/);

    if (!match) return null;

    const n = Number(match[0]);
    return Number.isFinite(n) ? n : null;
};

const pickAny = (row, names) => {
    if (!row) return '';

    for (const name of names) {
        if (Object.prototype.hasOwnProperty.call(row, name)) {
            const v = row[name];

            if (String(v ?? '').trim() !== '') {
                return v;
            }
        }
    }

    return '';
};

const firstNonBlank = (...values) => {
    for (const item of values) {
        const text = String(item ?? '').trim();

        if (text && text !== '-' && text.toLowerCase() !== 'null' && text.toLowerCase() !== 'undefined') {
            return item;
        }
    }

    return '';
};

const getCpuPercent = (row) => {
    return parsePercent(pickAny(row, [
        'cpu_usage',
        'cpu_utilization',
        'cpu_percent',
        'CPUUsage',
        'CPU_Usage',
        'CPUUtilization',
        'CPU_Utilization',
        'CPU',
        'processor_usage'
    ]));
};

const getMemoryPercent = (row) => {
    return parsePercent(pickAny(row, [
        'memory_usage',
        'memory_utilization',
        'memory_percent',
        'MemoryUsage',
        'Memory_Usage',
        'MemoryUtilization',
        'Memory_Utilization',
        'RAMUsage',
        'RAM_Usage',
        'RAM'
    ]));
};

const getHddPercent = (row) => {
    return parsePercent(pickAny(row, [
        'hdd_usage',
        'hdd_utilization',
        'hdd_percent',
        'disk_usage',
        'disk_utilization',
        'disk_percent',
        'HDDUsage',
        'HDD_Usage',
        'HDDUtilization',
        'HDD_Utilization',
        'DiskUsage',
        'Disk_Usage',
        'DiskUtilization',
        'Disk_Utilization',
        'drive_usage',
        'DriveUsage',
        'Drive_Usage'
    ]));
};

const formatPercent = (n) => {
    if (n === null || n === undefined || Number.isNaN(n)) return '-';
    return `${n}%`;
};

const getMetricStatus = (row) => {
    const values = [
        getCpuPercent(row),
        getMemoryPercent(row),
        getHddPercent(row)
    ].filter((n) => n !== null);

    if (values.some((n) => n >= CRITICAL_THRESHOLD)) return 'Critical';
    if (values.some((n) => n >= WARNING_THRESHOLD)) return 'Warning';

    return 'Normal';
};

const isMetricWarningRow = (row) => {
    const status = getMetricStatus(row);
    return status === 'Warning' || status === 'Critical';
};

const isCollectionFailedRow = (row) => {
    if (!row) return false;

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
            const key = normalizeHostKey(raw.hostname || raw.Hostname || raw.computer_name || raw.ComputerName || raw.Computer_Name);

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
            const key = normalizeHostKey(row.hostname || row.Hostname || row.computer_name || row.ComputerName || row.Computer_Name);
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

const getTitle = (view, issue) => {
    const v = String(view || '').toLowerCase();
    const i = String(issue || '').toLowerCase();

    if (i === 'collectionfailed' || i === 'collection-failed') return 'Collection Failed Endpoints';
    if (i === 'metricwarning' || i === 'metric-warning') return 'Metric Warning Endpoints';
    if (v === 'compliant') return 'Compliant Endpoints';
    if (v === 'partial') return 'Partial Compliant Endpoints';
    if (v === 'noncompliant' || v === 'non-compliant') return 'Non-Compliant Endpoints';
    if (v === 'unknown' || v === 'biosunknown' || v === 'bios-unknown') return 'BIOS Password Unknown Endpoints';

    return 'Results History';
};

const ResultsHistory = () => {
    const params = new URLSearchParams(window.location.search);
    const view = params.get('view') || 'all';
    const issue = params.get('issue') || '';

    const normalizedView = String(view || '').toLowerCase();
    const normalizedIssue = String(issue || '').toLowerCase();
    const isComplianceReportView = normalizedView === 'compliance' || normalizedView === 'compliance-report' || normalizedIssue === 'compliance';

    const isCollectionFailedView = normalizedIssue === 'collectionfailed' || normalizedIssue === 'collection-failed';
    const isMetricWarningView = normalizedIssue === 'metricwarning' || normalizedIssue === 'metric-warning';

    const isPartialView = normalizedView === 'partial' && !isCollectionFailedView && !isMetricWarningView;
    const canRescan = isPartialView || isCollectionFailedView || isMetricWarningView;
    const showExtendedColumns = !isMetricWarningView && (normalizedView === 'compliant' || normalizedView === 'partial' || isCollectionFailedView);

    const [rows, setRows] = useState([]);
    const [search, setSearch] = useState('');
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [selectedTargets, setSelectedTargets] = useState([]);
    const [rescanLoading, setRescanLoading] = useState(false);
    const [rescanMessage, setRescanMessage] = useState('');

    const loadResults = async () => {
        setLoading(true);
        setError('');

        try {
            const v = String(view || '').toLowerCase();
            let payload = [];

            if (isMetricWarningView) {
                payload = resultsService?.getResults ? await resultsService.getResults() : [];
            } else if (v === 'compliant') {
                payload = await complianceService.getCompliant();
            } else if (v === 'partial' || isCollectionFailedView) {
                payload = await complianceService.getPartial();
            } else if (v === 'noncompliant' || v === 'non-compliant') {
                payload = complianceService.getNonCompliant ? await complianceService.getNonCompliant() : [];
            } else if (v === 'unknown' || v === 'biosunknown' || v === 'bios-unknown') {
                payload = complianceService.getUnknown ? await complianceService.getUnknown() : [];
            } else {
                payload = resultsService?.getResults ? await resultsService.getResults() : [];
            }

            let dataRows = toRows(payload);

            if (isMetricWarningView) {
                dataRows = dataRows.filter(isMetricWarningRow);
            } else if (isCollectionFailedView) {
                dataRows = dataRows.filter(isCollectionFailedRow);
                dataRows = await enrichRowsFromRawResults(dataRows);
            } else if (normalizedView === 'partial') {
                dataRows = dataRows.filter((row) => !isCollectionFailedRow(row));
                dataRows = await enrichRowsFromRawResults(dataRows);
            } else if (showExtendedColumns) {
                dataRows = await enrichRowsFromRawResults(dataRows);
            }

            if (normalizedView === 'all' || normalizedView === 'history' || normalizedView === 'daily') {
                // Results History raw mode - no dedupe. Shows all scan attempts.
                setRows(dataRows);
            } else {
                // Current compliance views - latest unique host only.
                setRows(dedupeLatestRows(dataRows));
            }
            setSelectedTargets([]);
        } catch (err) {
            setError(err?.message || 'Failed to load results');
            setRows([]);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        loadResults();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [view, issue]);

    const filteredRows = useMemo(() => {
        const term = search.trim().toLowerCase();

        if (!term) return rows;

        return rows.filter((row) => Object.values(row || {}).some((v) => String(v ?? '').toLowerCase().includes(term)));
    }, [rows, search]);

    const visibleTargets = useMemo(() => filteredRows.map(getTargetName).filter(Boolean), [filteredRows]);
    const allVisibleSelected = visibleTargets.length > 0 && visibleTargets.every((target) => selectedTargets.includes(target));

    const toggleTarget = (target) => {
        if (!target) return;

        setSelectedTargets((current) => current.includes(target)
            ? current.filter((item) => item !== target)
            : [...current, target]
        );
    };

    const toggleAllVisible = () => {
        if (allVisibleSelected) {
            setSelectedTargets((current) => current.filter((target) => !visibleTargets.includes(target)));
        } else {
            setSelectedTargets((current) => Array.from(new Set([...current, ...visibleTargets])));
        }
    };

    const handleRescanSelected = async () => {
        if (selectedTargets.length === 0) {
            setRescanMessage('Please select at least one host to rescan.');
            return;
        }

        setRescanLoading(true);
        setError('');
        setRescanMessage('');

        try {
            await scanService.scanBulk(selectedTargets);
            setRescanMessage(`Rescan submitted for ${selectedTargets.length} host(s). Auto-refresh scheduled at 30, 60 and 120 seconds.`);
            setTimeout(() => loadResults(), 30000);
            setTimeout(() => loadResults(), 60000);
            setTimeout(() => loadResults(), 120000);
        } catch (err) {
            setError(err?.response?.data?.message || err?.message || 'Failed to submit selected hosts for rescan.');
        } finally {
            setRescanLoading(false);
        }
    };
    const exportCsv = () => {
        const exportRows = filteredRows || [];
        if (!exportRows.length) return;

        let columns = [];

        if (isMetricWarningView) {
            columns = [
                { key: 'host_name', label: 'Host Name', getValue: (row) => row.hostname || row.Hostname || row.computer_name || row.ComputerName },
                { key: 'domain_user', label: 'Domain User', getValue: (row) => row.domain_user || row.DomainUser },
                { key: 'cpu_percent', label: 'CPU %', getValue: (row) => formatPercent(getCpuPercent(row)) },
                { key: 'memory_percent', label: 'Memory %', getValue: (row) => formatPercent(getMemoryPercent(row)) },
                { key: 'hdd_percent', label: 'HDD %', getValue: (row) => formatPercent(getHddPercent(row)) },
                { key: 'metric_status', label: 'Metric Status', getValue: (row) => getMetricStatus(row) },
                { key: 'lastchecked', label: 'Last Checked', getValue: (row) => row.lastchecked || row.LastChecked }
            ];
        } else {
            columns = [
                { key: 'hostname', label: 'Hostname', getValue: (row) => row.hostname || row.Hostname || row.computer_name || row.ComputerName },
                { key: 'computer_name', label: 'ComputerName', getValue: (row) => row.computer_name || row.ComputerName || row.hostname || row.Hostname },
                { key: 'manufacturer', label: 'Manufacturer', getValue: (row) => row.manufacturer || row.Manufacturer },
                { key: 'model', label: 'Model', getValue: (row) => row.model || row.Model },
                { key: 'domain_user', label: 'DomainUser', getValue: (row) => row.domain_user || row.DomainUser },
                { key: 'poweron_password', label: 'Poweron Password', getValue: (row) => row.poweron_password },
                { key: 'admin_password', label: 'Admin Password', getValue: (row) => row.admin_password },
                { key: 'timesync_with_ntp', label: 'Time Sync With NTP', getValue: (row) => row.timesync_with_ntp },
                { key: 'readonly_usb', label: 'Read Only USB', getValue: (row) => row.readonly_usb },
                { key: 'screensaver_policy', label: 'Screensaver', getValue: (row) => row.screensaver_policy },
                { key: 'restrict_software_installation_policy', label: 'Restrict Software', getValue: (row) => row.restrict_software_installation_policy },
                { key: 'all_security_kbs', label: 'All Security KBs', getValue: (row) => row.all_security_kbs },
                { key: 'all_security_kbs_installedon', label: 'All Security KBs InstalledOn', getValue: (row) => row.all_security_kbs_installedon },
                { key: 'os_edition', label: 'OS Edition', getValue: (row) => row.os_edition || row.OS_Edition },
                { key: 'os_version', label: 'OS Version', getValue: (row) => row.os_version || row.OS_Version },
                { key: 'os_build', label: 'OS Build', getValue: (row) => row.os_build || row.OS_Build },
                { key: 'symantec_management_agent', label: 'Symantec Management Agent', getValue: (row) => row.symantec_management_agent || row.Symantec_Management_Agent },
                { key: 'compliance_issues', label: 'Compliance Issues', getValue: (row) => row.compliance_issues },
                { key: 'compliance_warnings', label: 'Compliance Warnings', getValue: (row) => row.compliance_warnings },
                { key: 'comments', label: 'Comments', getValue: (row) => row.comments },
                { key: 'lastchecked', label: 'Last Checked', getValue: (row) => row.lastchecked || row.LastChecked }
            ];
        }

        const header = columns.map((column) => csvEscape(column.label)).join(',');
        const body = exportRows.map((row) => columns.map((column) => csvEscape(column.getValue(row))).join(','));
        const csv = [header, ...body].join('\r\n');
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');

        link.href = url;
        link.download = `EMS_Results_History_${timestamp}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    };


    const columnCount = isMetricWarningView
        ? 8
        : ((showExtendedColumns ? 18 : 12) + (canRescan ? 1 : 0));
    if (isComplianceReportView) {
        return <ComplianceReport />;
    }

    // EMS_PATCH_RESULTS_HISTORY_COMMENT_REASON_V1_BEGIN
    const emsNormalizeText = (value) => String(value ?? '').trim();

    const emsFirstText = (...values) => {
        for (const value of values) {
            const text = emsNormalizeText(value);
            if (text && text !== '-' && text.toLowerCase() !== 'null' && text.toLowerCase() !== 'undefined') {
                return text;
            }
        }
        return '';
    };

    const emsGetCollectionStatusText = (row) => emsFirstText(
        row?.collection_status,
        row?.collectionStatus,
        row?.scan_status,
        row?.scanStatus,
        row?.status,
        row?.compliance_status,
        row?.complianceStatus,
        row?.result,
        row?.scan_result
    );

    const emsGetRawFailureReason = (row) => emsFirstText(
        row?.comment,
        row?.comments,
        row?.remarks,
        row?.remark,
        row?.error_message,
        row?.errorMessage,
        row?.collection_error,
        row?.collectionError,
        row?.failure_reason,
        row?.failureReason,
        row?.message,
        row?.scan_error,
        row?.scanError,
        row?.inventory_error,
        row?.inventoryError,
        row?.exception,
        row?.last_error,
        row?.lastError
    );

    const emsIsCollectionFailedRow = (row) => {
        const status = emsGetCollectionStatusText(row).toLowerCase();
        const reason = emsGetRawFailureReason(row).toLowerCase();
        const combined = `${status} ${reason}`;

        return (
            combined.includes('collection failed') ||
            combined.includes('inventory collection failed') ||
            combined.includes('rpc server is unavailable') ||
            combined.includes('rpc unavailable') ||
            combined.includes('unreachable') ||
            combined.includes('not reachable') ||
            combined.includes('access is denied') ||
            combined.includes('failed')
        );
    };

    const emsGetCommentText = (row) => {
        const reason = emsGetRawFailureReason(row);
        const status = emsGetCollectionStatusText(row);

        if (emsIsCollectionFailedRow(row)) {
            const cleanReason = reason || status || 'Reason not available';
            if (cleanReason.toLowerCase().startsWith('inventory collection failed')) {
                return cleanReason;
            }
            return `Inventory collection failed: ${cleanReason}`;
        }

        return reason || row?.comment || row?.comments || '-';
    };
    // EMS_PATCH_RESULTS_HISTORY_COMMENT_REASON_V1_END
    return (
        <div>
            <h1>{getTitle(view, issue)}</h1>

            {canRescan && (
                <div className="card" style={{ display: 'flex', gap: '12px', alignItems: 'center', flexWrap: 'wrap' }}>
                    <button className="btn btn-primary" onClick={handleRescanSelected} disabled={rescanLoading || selectedTargets.length === 0}>
                        {rescanLoading ? 'Submitting Rescan...' : `Rescan Selected (${selectedTargets.length})`}
                    </button>
                    <button className="btn" onClick={loadResults} disabled={loading || rescanLoading}>
                        Refresh List
                    </button>
                    <span>
                        {isMetricWarningView
                            ? `Metric Warning includes CPU/Memory/HDD >= ${WARNING_THRESHOLD}%. Critical is >= ${CRITICAL_THRESHOLD}%.`
                            : 'After scan completes, refreshed compliance classification will move remediated hosts automatically.'}
                    </span>
                </div>
            )}

            {rescanMessage && (
                <div className="card" style={{ color: '#155724', background: '#d4edda' }}>
                    {rescanMessage}
                </div>
            )}
            {/* EMS Results History CSV Export */}
            <div className="card" style={{ display: 'flex', gap: '12px', alignItems: 'center', flexWrap: 'wrap' }}>
                <button className="btn btn-primary" onClick={exportCsv} disabled={filteredRows.length === 0}>
                    Export CSV
                </button>
                <span>Showing {filteredRows.length} row(s)</span>
            </div>

            <input
                className="form-control"
                placeholder="Search..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                style={{ marginBottom: '12px' }}
            />

            {loading && <div className="card">Loading results...</div>}

            {!loading && error && (
                <div className="card" style={{ color: '#721c24', background: '#f8d7da' }}>
                    {error}
                </div>
            )}

            {!loading && !error && (
                <div className="table-container">
                    <table>
                        <thead>
                            {isMetricWarningView ? (
                                <tr>
                                    <th>
                                        <input type="checkbox" checked={allVisibleSelected} onChange={toggleAllVisible} />
                                    </th>
                                    <th>Host Name</th>
                                    <th>Domain User</th>
                                    <th>CPU %</th>
                                    <th>Memory %</th>
                                    <th>HDD %</th>
                                    <th>Metric Status</th>
                                    <th>Last Checked</th>
                                {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TH_V1_BEGIN */}
                                <th>Comment</th>
                                <th>Actions</th>
                                {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TH_V1_END */}
                                </tr>
                            ) : (
                                <tr>
                                    {canRescan && (
                                        <th>
                                            <input type="checkbox" checked={allVisibleSelected} onChange={toggleAllVisible} />
                                        </th>
                                    )}
                                    <th>Hostname</th>
                                    <th>ComputerName</th>
                                    <th>Manufacturer</th>
                                    <th>Model</th>
                                    <th>DomainUser</th>
                                    <th>Poweron Password</th>
                                    <th>Admin Password</th>
                                    <th>Time Sync With NTP</th>
                                    <th>Read Only USB</th>
                                    <th>Screensaver</th>
                                    <th>Restrict Software</th>
                                    {showExtendedColumns && <th>All Security KBs</th>}
                                    {showExtendedColumns && <th>All Security KBs InstalledOn</th>}
                                    {showExtendedColumns && <th>OS Edition</th>}
                                    {showExtendedColumns && <th>OS Version</th>}
                                    {showExtendedColumns && <th>OS Build</th>}
                                    {showExtendedColumns && <th>Symantec Management Agent</th>}
                                    <th>Last Checked</th>
                                {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TH_V1_BEGIN */}
                                <th>Comment</th>
                                <th>Actions</th>
                                {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TH_V1_END */}
                                </tr>
                            )}
                        </thead>
                        <tbody>
                            {filteredRows.length === 0 ? (
                                <tr>
                                    <td colSpan={columnCount} style={{ textAlign: 'center', padding: '20px' }}>No records found</td>
                                </tr>
                            ) : (
                                filteredRows.map((row, index) => {
                                    const target = getTargetName(row);

                                    if (isMetricWarningView) {
                                        return (
                                            <tr key={`${target || 'row'}-${index}`}>
                                                <td>
                                                    <input
                                                        type="checkbox"
                                                        checked={selectedTargets.includes(target)}
                                                        onChange={() => toggleTarget(target)}
                                                        disabled={!target}
                                                    />
                                                </td>
                                                <td>{value(row.hostname || row.Hostname || row.computer_name || row.ComputerName)}</td>
                                                <td>{value(row.domain_user || row.DomainUser)}</td>
                                                <td>{formatPercent(getCpuPercent(row))}</td>
                                                <td>{formatPercent(getMemoryPercent(row))}</td>
                                                <td>{formatPercent(getHddPercent(row))}</td>
                                                <td>{getMetricStatus(row)}</td>
                                                <td>{value(row.lastchecked || row.LastChecked)}</td>
                                    {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TD_V1_BEGIN */}
                                    <td title={emsGetCommentText(row)}>{emsGetCommentText(row)}</td>
                                    <td>
                                        {row.scan_id ? <Link to={`/scan/trace/${row.scan_id}`} className="btn btn-sm" style={{ padding: '2px 8px', fontSize: '0.75rem' }}>View Trace</Link> : '-'}
                                    </td>
                                    {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TD_V1_END */}
                                            </tr>
                                        );
                                    }

                                    return (
                                        <tr key={`${target || 'row'}-${index}`}>
                                            {canRescan && (
                                                <td>
                                                    <input
                                                        type="checkbox"
                                                        checked={selectedTargets.includes(target)}
                                                        onChange={() => toggleTarget(target)}
                                                        disabled={!target}
                                                    />
                                                </td>
                                            )}
                                            <td>{value(row.hostname || row.Hostname || row.computer_name || row.ComputerName)}</td>
                                            <td>{value(row.computer_name || row.ComputerName || row.hostname || row.Hostname)}</td>
                                            <td>{value(row.manufacturer || row.Manufacturer)}</td>
                                            <td>{value(row.model || row.Model)}</td>
                                            <td>{value(row.domain_user || row.DomainUser)}</td>
                                            <td>{value(row.poweron_password)}</td>
                                            <td>{value(row.admin_password)}</td>
                                            <td>{value(row.timesync_with_ntp)}</td>
                                            <td>{value(row.readonly_usb)}</td>
                                            <td>{value(row.screensaver_policy)}</td>
                                            <td>{value(row.restrict_software_installation_policy)}</td>
                                            {showExtendedColumns && <td>{value(row.all_security_kbs)}</td>}
                                            {showExtendedColumns && <td>{value(row.all_security_kbs_installedon)}</td>}
                                            {showExtendedColumns && <td>{value(row.os_edition)}</td>}
                                            {showExtendedColumns && <td>{value(row.os_version)}</td>}
                                            {showExtendedColumns && <td>{value(row.os_build)}</td>}
                                            {showExtendedColumns && <td>{value(row.symantec_management_agent)}</td>}
                                            <td>{value(row.lastchecked || row.LastChecked)}</td>
                                    {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TD_V1_BEGIN */}
                                    <td title={emsGetCommentText(row)}>{emsGetCommentText(row)}</td>
                                    {/* EMS_PATCH_RESULTS_HISTORY_COMMENT_TD_V1_END */}
                                        </tr>
                                    );
                                })
                            )}
                        </tbody>
                    </table>
                </div>
            )}
        </div>
    );
};

export default ResultsHistory;




