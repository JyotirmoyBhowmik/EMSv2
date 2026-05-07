CREATE TABLE IF NOT EXISTS scans (
    scan_id UUID PRIMARY KEY,
    target TEXT NOT NULL,

    status TEXT NOT NULL
        CHECK (status IN ('queued', 'running', 'completed', 'failed')),

    health_score INTEGER,
    critical_alerts INTEGER,
    warning_alerts INTEGER,
    info_alerts INTEGER,
    execution_time_sec INTEGER,

    result_json JSONB,
    error_message TEXT,

    started_at TIMESTAMP NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_scans_status
    ON scans (status);

CREATE INDEX IF NOT EXISTS idx_scans_started_at
    ON scans (started_at);