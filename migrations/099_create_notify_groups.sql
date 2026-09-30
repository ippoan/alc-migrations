-- notify_groups: 通知受信者のグループ (配信ターゲット指定用)
CREATE TABLE alc_api.notify_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, name)
);

-- notify_recipient_groups: メンバーシップ (多対多)
CREATE TABLE alc_api.notify_recipient_groups (
    group_id UUID NOT NULL REFERENCES alc_api.notify_groups(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES alc_api.notify_recipients(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, recipient_id)
);

CREATE INDEX idx_notify_recipient_groups_recipient
    ON alc_api.notify_recipient_groups(recipient_id);

-- RLS: notify_recipients と同じテナント分離ポリシー
ALTER TABLE alc_api.notify_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.notify_groups FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.notify_recipient_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.notify_recipient_groups FORCE ROW LEVEL SECURITY;

CREATE POLICY notify_groups_select ON alc_api.notify_groups
    FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::UUID);
CREATE POLICY notify_groups_insert ON alc_api.notify_groups
    FOR INSERT WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::UUID);
CREATE POLICY notify_groups_update ON alc_api.notify_groups
    FOR UPDATE USING (tenant_id = current_setting('app.current_tenant_id', true)::UUID);
CREATE POLICY notify_groups_delete ON alc_api.notify_groups
    FOR DELETE USING (tenant_id = current_setting('app.current_tenant_id', true)::UUID);

CREATE POLICY notify_recipient_groups_select ON alc_api.notify_recipient_groups
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM alc_api.notify_groups g
            WHERE g.id = notify_recipient_groups.group_id
              AND g.tenant_id = current_setting('app.current_tenant_id', true)::UUID
        )
    );
CREATE POLICY notify_recipient_groups_insert ON alc_api.notify_recipient_groups
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM alc_api.notify_groups g
            WHERE g.id = notify_recipient_groups.group_id
              AND g.tenant_id = current_setting('app.current_tenant_id', true)::UUID
        )
    );
CREATE POLICY notify_recipient_groups_delete ON alc_api.notify_recipient_groups
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM alc_api.notify_groups g
            WHERE g.id = notify_recipient_groups.group_id
              AND g.tenant_id = current_setting('app.current_tenant_id', true)::UUID
        )
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.notify_groups TO alc_api_app;
GRANT SELECT, INSERT, DELETE ON alc_api.notify_recipient_groups TO alc_api_app;
