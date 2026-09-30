-- テナントごとの Webhook 設定 (Req 5, 15)
CREATE TABLE webhook_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    event_type TEXT NOT NULL CHECK (event_type IN ('alcohol_detected', 'tenko_overdue', 'tenko_completed', 'tenko_cancelled')),
    url TEXT NOT NULL,
    secret TEXT,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, event_type)
);

ALTER TABLE webhook_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_webhook_configs ON webhook_configs
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
