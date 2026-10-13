-- 機械用資格情報 (複合機の WebDAV 送信の Basic 認証など)。
-- いままで auth-worker の KV に在り、会社と結び付いていなかったため、会社が消えても残り、
-- 一覧に出ず、revoke できなかった。DB の表に置き、tenants へ FK + ON DELETE CASCADE で結び付ける。
-- 平文のパスワードは保存しない (secret_hash = sha256 の hex)。比較は呼び出し側 (定数時間) が行う。

CREATE TABLE alc_api.machine_credentials (
    username TEXT PRIMARY KEY CHECK (username ~ '^mc_[0-9a-f]{16}$'),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL CHECK (purpose IN ('leave-scan')),
    label TEXT NOT NULL CHECK (char_length(label) BETWEEN 1 AND 64),
    secret_hash TEXT NOT NULL CHECK (secret_hash ~ '^[0-9a-f]{64}$'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_machine_credentials_tenant_purpose
    ON alc_api.machine_credentials (tenant_id, purpose);

ALTER TABLE alc_api.machine_credentials ENABLE ROW LEVEL SECURITY;
CREATE POLICY machine_credentials_tenant ON alc_api.machine_credentials
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.machine_credentials TO alc_api_app;

-- 照合用。username だけでは会社が分からない (会社をまたいで引く) ので SECURITY DEFINER。
-- username で 1 行 (無ければ 0 行)。hash を返すだけで、比較は呼び出し側。
CREATE FUNCTION alc_api.machine_credential_lookup(p_username TEXT)
RETURNS TABLE (tenant_id UUID, purpose TEXT, secret_hash TEXT, revoked BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT mc.tenant_id, mc.purpose, mc.secret_hash, mc.revoked_at IS NOT NULL
      FROM alc_api.machine_credentials mc
     WHERE mc.username = p_username;
$$;
REVOKE ALL ON FUNCTION alc_api.machine_credential_lookup(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.machine_credential_lookup(TEXT) TO alc_api_app, alc_api_rt;
