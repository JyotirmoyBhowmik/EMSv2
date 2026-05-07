-- Complete Database Deployment Script
-- Combines all schemas: base + granular metrics + multi-auth

-- First run the base schema (original)
\i schema.sql

-- Then add multi-auth support
\i migration_multi_auth.sql

-- Then create granular metrics tables
\i schema_granular_metrics_part1.sql
\i schema_granular_metrics_part2.sql

-- Grant permissions on all new tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ems_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ems_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ems_service;

-- Refresh materialized views
REFRESH MATERIALIZED VIEW dashboard_statistics;
REFRESH MATERIALIZED VIEW view_computer_health_summary;

-- Show summary
SELECT 'Database setup complete!' as status;
SELECT COUNT(*) as total_tables FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
SELECT COUNT(*) as total_functions FROM information_schema.routines WHERE routine_schema = 'public';
