-- LINE Login チャネル設定を notify_line_configs に追加 (テナントごと)

ALTER TABLE alc_api.notify_line_configs
    ADD COLUMN login_channel_id TEXT,
    ADD COLUMN login_channel_secret_encrypted TEXT;

-- lookup 関数を更新 (login_channel_id, login_channel_secret_encrypted を追加)
DROP FUNCTION IF EXISTS alc_api.lookup_line_config_by_channel(TEXT);
CREATE OR REPLACE FUNCTION alc_api.lookup_line_config_by_channel(p_channel_id TEXT)
RETURNS TABLE(
    id UUID,
    tenant_id UUID,
    channel_id TEXT,
    channel_secret_encrypted TEXT,
    channel_access_token_encrypted TEXT,
    key_id TEXT,
    private_key_encrypted TEXT,
    login_channel_id TEXT,
    login_channel_secret_encrypted TEXT
)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api
AS $$
    SELECT id, tenant_id, channel_id, channel_secret_encrypted, channel_access_token_encrypted,
           key_id, private_key_encrypted, login_channel_id, login_channel_secret_encrypted
    FROM alc_api.notify_line_configs
    WHERE channel_id = p_channel_id AND enabled = TRUE;
$$;
