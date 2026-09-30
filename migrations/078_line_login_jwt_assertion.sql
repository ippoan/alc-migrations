-- LINE Login を JWT assertion 方式に変更
-- login_channel_secret_encrypted → login_key_id (同じ秘密鍵を使い kid だけ別)

ALTER TABLE alc_api.notify_line_configs
    DROP COLUMN IF EXISTS login_channel_secret_encrypted,
    ADD COLUMN IF NOT EXISTS login_key_id TEXT;

-- lookup 関数を更新
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
    login_key_id TEXT
)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api
AS $$
    SELECT id, tenant_id, channel_id, channel_secret_encrypted, channel_access_token_encrypted,
           key_id, private_key_encrypted, login_channel_id, login_key_id
    FROM alc_api.notify_line_configs
    WHERE channel_id = p_channel_id AND enabled = TRUE;
$$;
