-- 有給の期首残 (X 日時点の残)。乗務員 1 人につき 1 行で、「前年からの繰越 (carryover)」と
-- 「今年度の付与の残 (current)」の 2 つを持つ (失効日を正確にするため 2 つに分ける)。
-- 残の計算 (X = as_of として合成の付与 2 件にする) と口は rust-leave-worker 側で行う。
-- 付与台帳 leave_grants (163) には手を入れない (Refs ohishi-exp/rust-leave-worker#1)。
-- 乗務員は一番星の 社員C (employee_cd) を文字列で持つ (leave_grants と同じ)。
--
-- ポリシーは 163 の leave_grants と同じ形 (NULLIF で未設定を NULL にし、USING と WITH CHECK の両方に書く)。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。
CREATE TABLE alc_api.leave_opening (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    employee_cd TEXT NOT NULL,
    as_of DATE NOT NULL,
    carryover NUMERIC(4,1) NOT NULL DEFAULT 0 CHECK (carryover >= 0),
    current NUMERIC(4,1) NOT NULL DEFAULT 0 CHECK (current >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, employee_cd)
);

ALTER TABLE alc_api.leave_opening ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.leave_opening FORCE ROW LEVEL SECURITY;
CREATE POLICY leave_opening_tenant ON alc_api.leave_opening
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.leave_opening TO alc_api_app;
