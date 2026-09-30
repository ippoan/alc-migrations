-- LINE WORKS Bot が招待されたトークルーム/グループのチャネル情報を保持
-- + bot_configs に webhook 署名検証用 bot_secret 暗号化カラムを追加
--
-- 機能要件: ユーザーが LINE WORKS アプリ上で対象トークルームに Bot を手動で招待
-- → Bot が `joined` イベントを受信 → webhook で channel_id を保存 → notify 配信先として利用

-- 1) bot_configs に webhook 署名検証用 secret カラム追加
ALTER TABLE alc_api.bot_configs
    ADD COLUMN IF NOT EXISTS bot_secret_encrypted TEXT;

-- 2) Bot が招待されたチャネル (トークルーム/グループ) を保持
CREATE TABLE IF NOT EXISTS alc_api.lineworks_channels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    bot_config_id UUID NOT NULL REFERENCES alc_api.bot_configs(id) ON DELETE CASCADE,
    channel_id TEXT NOT NULL,        -- LINE WORKS channel/group ID
    title TEXT,                       -- 取得できた場合のグループ名
    channel_type TEXT,                -- "group" | "domain" | "user" 等
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_lwc_bot_channel
    ON alc_api.lineworks_channels(bot_config_id, channel_id);
CREATE INDEX IF NOT EXISTS idx_lwc_tenant
    ON alc_api.lineworks_channels(tenant_id) WHERE active = TRUE;

ALTER TABLE alc_api.lineworks_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.lineworks_channels FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON alc_api.lineworks_channels
    USING (tenant_id = COALESCE(
        NULLIF(current_setting('app.current_tenant_id', true), '')::UUID,
        NULLIF(current_setting('app.current_organization_id', true), '')::UUID
    ))
    WITH CHECK (tenant_id = COALESCE(
        NULLIF(current_setting('app.current_tenant_id', true), '')::UUID,
        NULLIF(current_setting('app.current_organization_id', true), '')::UUID
    ));

GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.lineworks_channels TO alc_api_app;

-- 3) webhook が bot_id から bot_config を引くための SECURITY DEFINER lookup
--    (webhook は認証なしで叩かれるので RLS をバイパスして bot_id → tenant_id 解決)
CREATE OR REPLACE FUNCTION alc_api.lookup_bot_config_for_webhook(p_bot_id TEXT)
RETURNS TABLE (id UUID, tenant_id UUID, bot_secret_encrypted TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = alc_api
AS $$
    SELECT id, tenant_id, bot_secret_encrypted
    FROM alc_api.bot_configs
    WHERE bot_id = p_bot_id AND enabled = TRUE
    LIMIT 1
$$;

GRANT EXECUTE ON FUNCTION alc_api.lookup_bot_config_for_webhook(TEXT) TO alc_api_app;
