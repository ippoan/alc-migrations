-- 点呼実施予定 (Req 1, 14, 15)
CREATE TABLE tenko_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    employee_id UUID NOT NULL REFERENCES employees(id),
    tenko_type TEXT NOT NULL CHECK (tenko_type IN ('pre_operation', 'post_operation')),
    responsible_manager_name TEXT NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    instruction TEXT,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    consumed_by_session_id UUID,
    overdue_notified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- 業務前は指示事項必須
    CONSTRAINT chk_pre_operation_instruction
        CHECK (tenko_type != 'pre_operation' OR instruction IS NOT NULL)
);

CREATE INDEX idx_tenko_schedules_tenant ON tenko_schedules(tenant_id);
CREATE INDEX idx_tenko_schedules_employee ON tenko_schedules(tenant_id, employee_id);
CREATE INDEX idx_tenko_schedules_pending ON tenko_schedules(tenant_id, consumed)
    WHERE consumed = FALSE;
CREATE INDEX idx_tenko_schedules_scheduled_at ON tenko_schedules(tenant_id, scheduled_at);

ALTER TABLE tenko_schedules ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_tenko_schedules ON tenko_schedules
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
