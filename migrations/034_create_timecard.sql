-- タイムカード用カード登録テーブル (多:1 = カード:社員)
CREATE TABLE alc_api.timecard_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    employee_id UUID NOT NULL REFERENCES alc_api.employees(id),
    card_id TEXT NOT NULL,
    label TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_timecard_cards_unique ON alc_api.timecard_cards(tenant_id, card_id);
CREATE INDEX idx_timecard_cards_employee ON alc_api.timecard_cards(tenant_id, employee_id);

ALTER TABLE alc_api.timecard_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_timecard_cards ON alc_api.timecard_cards
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- 打刻テーブル
CREATE TABLE alc_api.time_punches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    employee_id UUID NOT NULL REFERENCES alc_api.employees(id),
    punched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_time_punches_tenant ON alc_api.time_punches(tenant_id);
CREATE INDEX idx_time_punches_employee_date ON alc_api.time_punches(tenant_id, employee_id, punched_at DESC);

ALTER TABLE alc_api.time_punches ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_time_punches ON alc_api.time_punches
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
