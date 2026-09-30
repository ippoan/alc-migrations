-- API tokens for machine-to-machine access (nuxt-dtako-admin /api/api-tokens)
-- 平文トークンは発行時のみ表示、DB には SHA-256 ハッシュで保存する。
-- 失効はソフトデリート (revoked_at)。

CREATE TABLE alc_api.api_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    token_prefix TEXT NOT NULL,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_api_tokens_tenant_id ON alc_api.api_tokens(tenant_id);
CREATE INDEX idx_api_tokens_token_hash ON alc_api.api_tokens(token_hash);

-- RLS: テナント境界
ALTER TABLE alc_api.api_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON alc_api.api_tokens
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.api_tokens TO alc_api_app;
