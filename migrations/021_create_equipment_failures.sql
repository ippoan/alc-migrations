-- 機器故障記録 (要件17)
CREATE TABLE IF NOT EXISTS equipment_failures (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    failure_type TEXT NOT NULL CHECK (failure_type IN (
        'face_recognition_error',
        'measurement_recording_failed',
        'kiosk_offline',
        'database_sync_error',
        'webhook_delivery_failed',
        'session_state_error',
        'photo_storage_error',
        'manual_report'
    )),
    description TEXT NOT NULL,
    affected_device TEXT,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    detected_by TEXT,
    resolved_at TIMESTAMPTZ,
    resolution_notes TEXT,
    session_id UUID REFERENCES tenko_sessions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_equipment_failures_tenant ON equipment_failures(tenant_id);
CREATE INDEX IF NOT EXISTS idx_equipment_failures_type ON equipment_failures(tenant_id, failure_type);
CREATE INDEX IF NOT EXISTS idx_equipment_failures_unresolved ON equipment_failures(tenant_id)
    WHERE resolved_at IS NULL;

ALTER TABLE equipment_failures ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'equipment_failures' AND policyname = 'tenant_isolation_equipment_failures'
    ) THEN
        CREATE POLICY tenant_isolation_equipment_failures ON equipment_failures
            USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON equipment_failures TO alc_api_app;
