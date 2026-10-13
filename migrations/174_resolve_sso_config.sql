-- resolve_sso_config を migration の履歴に取り込む。
--
-- ログインの内部口 (SSO 設定の引き当て) が使う SECURITY DEFINER 関数。本番では Supabase の
-- ダッシュボードで手作業で作られ、履歴に無かった (scripts/init_local_db.sql にだけ定義があった)。
-- 履歴に無いと、migration を 0 から流す DB (staging 等) に作られない。
--
-- 定義 (引数名・戻りの列・言語・本文) は scripts/init_local_db.sql にあったものをそのまま写す。
-- 規範に合わせて足したのは REVOKE / GRANT だけ (SECURITY DEFINER と SET search_path は元からある)。
--
-- 先頭の DROP FUNCTION IF EXISTS: 本番の既存の関数は引数名が確かめられていない。CREATE OR REPLACE は
-- 引数名が違うと "cannot change name of input parameter" で失敗するので、先に落として作り直す
-- (同じ migration の transaction の中。権限は下の REVOKE / GRANT で明示する)。
DROP FUNCTION IF EXISTS alc_api.resolve_sso_config(TEXT, TEXT);

CREATE OR REPLACE FUNCTION alc_api.resolve_sso_config(
    p_provider TEXT,
    p_lookup_key TEXT
) RETURNS TABLE (
    tenant_id UUID,
    client_id TEXT,
    client_secret_encrypted TEXT,
    external_org_id TEXT,
    woff_id TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT sso.tenant_id, sso.client_id, sso.client_secret_encrypted,
           sso.external_org_id, sso.woff_id
    FROM alc_api.sso_provider_configs sso
    WHERE sso.provider = p_provider
      AND sso.external_org_id = p_lookup_key
      AND sso.enabled = true
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = alc_api;

REVOKE ALL ON FUNCTION alc_api.resolve_sso_config(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.resolve_sso_config(TEXT, TEXT) TO alc_api_app, alc_api_rt;
