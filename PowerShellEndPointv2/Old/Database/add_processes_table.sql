-- Migration: Add metric_processes table
-- Description: Stores snapshot of running processes

CREATE TABLE IF NOT EXISTS metric_processes (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    process_id INTEGER,
    process_name VARCHAR(255),
    path VARCHAR(1000),
    working_set_mb DECIMAL(10,2),
    cpu_usage_percent DECIMAL(5,2),
    user_name VARCHAR(255),
    is_critical BOOLEAN DEFAULT false,
    PRIMARY KEY (computer_name, timestamp, process_id)
);

CREATE INDEX idx_processes_name ON metric_processes(process_name);
CREATE INDEX idx_processes_timestamp ON metric_processes(timestamp DESC);

-- Update schema version
INSERT INTO schema_version (version, description) 
VALUES ('1.1.1', 'Added metric_processes table');
