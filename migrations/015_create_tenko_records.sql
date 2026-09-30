-- 点呼記録 — 不変レコード (Req 16, 18)
CREATE TABLE tenko_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    session_id UUID NOT NULL REFERENCES tenko_sessions(id),
    employee_id UUID NOT NULL REFERENCES employees(id),
    tenko_type TEXT NOT NULL,
    status TEXT NOT NULL,
    record_data JSONB NOT NULL,
    employee_name TEXT NOT NULL,
    responsible_manager_name TEXT NOT NULL,
    tenko_method TEXT NOT NULL DEFAULT '自動点呼',
    location TEXT,
    alcohol_result TEXT,
    alcohol_value DOUBLE PRECISION,
    alcohol_has_face_photo BOOLEAN NOT NULL DEFAULT FALSE,
    temperature DOUBLE PRECISION,
    systolic INTEGER,
    diastolic INTEGER,
    pulse INTEGER,
    instruction TEXT,
    instruction_confirmed_at TIMESTAMPTZ,
    report_vehicle_road_status TEXT,
    report_driver_alternation TEXT,
    report_no_report BOOLEAN,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    record_hash TEXT NOT NULL
);

CREATE INDEX idx_tenko_records_tenant ON tenko_records(tenant_id);
CREATE INDEX idx_tenko_records_employee ON tenko_records(tenant_id, employee_id);
CREATE INDEX idx_tenko_records_session ON tenko_records(session_id);
CREATE INDEX idx_tenko_records_date ON tenko_records(tenant_id, recorded_at DESC);

ALTER TABLE tenko_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_tenko_records ON tenko_records
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- 改ざん防止: UPDATE/DELETE を禁止
CREATE OR REPLACE FUNCTION prevent_tenko_record_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'tenko_records cannot be modified or deleted (tamper prevention)';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_tenko_record_update
    BEFORE UPDATE ON tenko_records
    FOR EACH ROW
    EXECUTE FUNCTION prevent_tenko_record_modification();

CREATE TRIGGER trg_prevent_tenko_record_delete
    BEFORE DELETE ON tenko_records
    FOR EACH ROW
    EXECUTE FUNCTION prevent_tenko_record_modification();
