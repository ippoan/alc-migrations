-- 健康状態基準値管理 (要件7)
CREATE TABLE IF NOT EXISTS employee_health_baselines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    employee_id UUID NOT NULL REFERENCES employees(id),
    -- 基準値
    baseline_systolic INTEGER NOT NULL DEFAULT 120,
    baseline_diastolic INTEGER NOT NULL DEFAULT 80,
    baseline_temperature DOUBLE PRECISION NOT NULL DEFAULT 36.5,
    -- 許容範囲 (±)
    systolic_tolerance INTEGER NOT NULL DEFAULT 10,
    diastolic_tolerance INTEGER NOT NULL DEFAULT 10,
    temperature_tolerance DOUBLE PRECISION NOT NULL DEFAULT 0.5,
    -- 測定値有効時間 (分)
    measurement_validity_minutes INTEGER NOT NULL DEFAULT 30,
    -- メタデータ
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- 1乗務員1レコード
    UNIQUE (tenant_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_health_baselines_tenant ON employee_health_baselines(tenant_id);
CREATE INDEX IF NOT EXISTS idx_health_baselines_employee ON employee_health_baselines(tenant_id, employee_id);

ALTER TABLE employee_health_baselines ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'employee_health_baselines' AND policyname = 'tenant_isolation_health_baselines'
    ) THEN
        CREATE POLICY tenant_isolation_health_baselines ON employee_health_baselines
            USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
    END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON employee_health_baselines TO alc_api_app;
