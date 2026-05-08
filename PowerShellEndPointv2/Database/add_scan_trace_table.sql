-- Migration: Add scan_trace table for real-time scan observability
-- Description: Tracks individual steps of a scan in progress

CREATE TABLE IF NOT EXISTS scan_trace (
    trace_id BIGSERIAL PRIMARY KEY,
    scan_id BIGINT NOT NULL,
    step_name VARCHAR(100) NOT NULL,
    module_name VARCHAR(100) NOT NULL,
    status VARCHAR(50) DEFAULT 'Info' CHECK (status IN ('Info', 'Success', 'Warning', 'Error')),
    message TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- No foreign key to scan_results because scan_results is partitioned
    -- and we don't want trace logs to block partition routing or be deleted with partitions if we want to keep them longer.
    -- However, for performance, we index the scan_id.
    CONSTRAINT fk_scan_trace_scan_id FOREIGN KEY (scan_id) REFERENCES scan_results(scan_id) ON DELETE CASCADE
) NOT PARTITIONED; -- Traces are ephemeral but useful for debugging

CREATE INDEX idx_scan_trace_scan_id ON scan_trace(scan_id);
CREATE INDEX idx_scan_trace_timestamp ON scan_trace(timestamp DESC);

-- Update schema version
INSERT INTO schema_version (version, description) 
VALUES ('1.1.0', 'Added scan_trace table for real-time observability');
