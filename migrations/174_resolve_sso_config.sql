-- resolve_sso_config を migration の履歴に取り込む。
--
-- ログインの内部口 (SSO 設定の引き当て) が使う SECURITY DEFINER 関数。本番では Supabase の
-- ダッシュボードで手作業で作られ、履歴に無かった。履歴に無いと、migration を 0 から流す DB
-- (staging 等) に作られない。
--
-- 定義は、本番の pg_get_functiondef (2026-10-13) をそのまま写したもの。引数名・戻りの列・言語・本文は
-- 本番のとおり (external_org_id で完全一致し、見つからなければ tenants.slug で引き直す)。
-- 引数名が本番と同じなので、先に DROP せず CREATE OR REPLACE にする (本番の既存の権限も保たれる)。
-- 規範に合わせて足したのは REVOKE / GRANT だけ (SECURITY DEFINER と SET search_path は本番にある)。
CREATE OR REPLACE FUNCTION alc_api.resolve_sso_config(p_provider text, p_domain text)
 RETURNS TABLE(tenant_id uuid, client_id text, client_secret_encrypted text, external_org_id text, woff_id text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'alc_api'
AS $function$
BEGIN
    -- external_org_id で完全一致
    RETURN QUERY
    SELECT c.tenant_id, c.client_id, c.client_secret_encrypted, c.external_org_id, c.woff_id
    FROM sso_provider_configs c
    WHERE c.provider = p_provider
      AND c.external_org_id = p_domain
      AND c.enabled = TRUE
    LIMIT 1;

    IF NOT FOUND THEN
        -- tenant slug でフォールバック
        RETURN QUERY
        SELECT c.tenant_id, c.client_id, c.client_secret_encrypted, c.external_org_id, c.woff_id
        FROM sso_provider_configs c
        JOIN tenants t ON t.id = c.tenant_id
        WHERE c.provider = p_provider
          AND t.slug = p_domain
          AND c.enabled = TRUE
        LIMIT 1;
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION alc_api.resolve_sso_config(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.resolve_sso_config(TEXT, TEXT) TO alc_api_app, alc_api_rt;

-- sso_provider_configs は 048 で FORCE ROW LEVEL SECURITY。FORCE があると表の所有者 (alc_api_app =
-- この関数の所有者) にもポリシーが掛かり、ログイン前の呼び出し (app.current_tenant_id が空) では
-- 上の SECURITY DEFINER 関数が 0 行しか返さない (本番では関数の所有者が alc_api_app でないため動いている)。
-- 118〜120・161 と同じ理由と同じ手当てで、FORCE を外す。
-- backend の実行用ロール alc_api_rt は表の所有者でないので、RLS は引き続き掛かる
-- (FORCE が影響するのは所有者のコンテキストだけ)。
ALTER TABLE alc_api.sso_provider_configs NO FORCE ROW LEVEL SECURITY;
