-- 点呼セッション — 状態管理の中心エンティティ
CREATE TABLE tenko_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    employee_id UUID NOT NULL REFERENCES employees(id),
    schedule_id UUID NOT NULL REFERENCES tenko_schedules(id),
    tenko_type TEXT NOT NULL CHECK (tenko_type IN ('pre_operation', 'post_operation')),
    status TEXT NOT NULL DEFAULT 'identity_verified'
        CHECK (status IN (
            'identity_verified',
            'alcohol_testing',
            'instruction_pending',
            'report_pending',
            'completed',
            'cancelled',
            'interrupted'
        )),
    -- 本人確認
    identity_verified_at TIMESTAMPTZ,
    identity_face_photo_url TEXT,
    -- アルコール測定
    measurement_id UUID REFERENCES measurements(id),
    alcohol_result TEXT CHECK (alcohol_result IS NULL OR alcohol_result IN ('pass', 'fail', 'normal', 'over', 'error')),
    alcohol_value DOUBLE PRECISION,
    alcohol_tested_at TIMESTAMPTZ,
    alcohol_face_photo_url TEXT,
    -- 医療データ (業務前)
    temperature DOUBLE PRECISION,
    systolic INTEGER,
    diastolic INTEGER,
    pulse INTEGER,
    medical_measured_at TIMESTAMPTZ,
    -- 指示事項確認
    instruction_confirmed_at TIMESTAMPTZ,
    -- 運行状況報告 (業務後)
    report_vehicle_road_status TEXT,
    report_driver_alternation TEXT,
    report_no_report BOOLEAN,
    report_submitted_at TIMESTAMPTZ,
    -- 場所
    location TEXT,
    -- 管理者情報
    responsible_manager_name TEXT NOT NULL,
    -- 中止理由
    cancel_reason TEXT,
    -- 中断→再開 (Phase 2)
    interrupted_at TIMESTAMPTZ,
    resumed_at TIMESTAMPTZ,
    resume_reason TEXT,
    resumed_by_user_id UUID,
    -- タイムスタンプ
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tenko_sessions_tenant ON tenko_sessions(tenant_id);
CREATE INDEX idx_tenko_sessions_employee ON tenko_sessions(tenant_id, employee_id);
CREATE INDEX idx_tenko_sessions_schedule ON tenko_sessions(schedule_id);
CREATE INDEX idx_tenko_sessions_status ON tenko_sessions(tenant_id, status)
    WHERE status NOT IN ('completed', 'cancelled');
CREATE INDEX idx_tenko_sessions_measurement ON tenko_sessions(measurement_id)
    WHERE measurement_id IS NOT NULL;

ALTER TABLE tenko_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_tenko_sessions ON tenko_sessions
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- tenko_schedules に FK を追加
ALTER TABLE tenko_schedules
    ADD CONSTRAINT fk_consumed_by_session
    FOREIGN KEY (consumed_by_session_id) REFERENCES tenko_sessions(id);
