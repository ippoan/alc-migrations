-- Enable Row Level Security
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE measurements ENABLE ROW LEVEL SECURITY;

-- RLS policies: isolate by tenant_id using session variable
CREATE POLICY tenant_isolation_employees ON employees
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

CREATE POLICY tenant_isolation_measurements ON measurements
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- Application role (non-superuser) for RLS enforcement
-- Note: Create this role during deployment setup:
--   CREATE ROLE app_user LOGIN PASSWORD '...';
--   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
