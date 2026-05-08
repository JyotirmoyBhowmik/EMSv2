-- =====================================================
-- EMS Optimization: Indexing for Dashboard Performance
-- =====================================================

-- Index for scan status and deletion (Dashboard filtering)
CREATE INDEX IF NOT EXISTS idx_scans_dashboard_filter 
ON scans (status, is_deleted, completed_at) 
WHERE is_deleted = false;

-- Index for latest scan per target (Compliance view performance)
CREATE INDEX IF NOT EXISTS idx_scans_target_latest 
ON scans (target, completed_at DESC) 
WHERE is_deleted = false;

-- Index for result lookups
CREATE INDEX IF NOT EXISTS idx_scan_inventory_scan_id 
ON scan_inventory_results (scan_id);

-- Index for trace observability
CREATE TABLE IF NOT EXISTS scan_trace (
    trace_id SERIAL PRIMARY KEY,
    scan_id UUID NOT NULL REFERENCES scans(scan_id) ON DELETE CASCADE,
    step_name VARCHAR(255) NOT NULL,
    module_name VARCHAR(255),
    status VARCHAR(50),
    message TEXT,
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scan_trace_scan_id 
ON scan_trace (scan_id, timestamp ASC);
