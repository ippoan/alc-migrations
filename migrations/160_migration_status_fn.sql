-- 適用履歴 (件数と最大 version) を、実行用ロール alc_api_rt の接続から読めるようにする
-- Refs ippoan/auth-worker#605
--
-- migration を本番に当てた後、「どこまで当たっているか」を backend の接続から確かめたい。
-- backend は alc_api_rt で繋ぐが、alc_api_rt は _sqlx_migrations の権限を持たない (migration 158)。
-- 表そのものの権限は変えず、件数と最大 version の 2 値だけを返す SECURITY DEFINER 関数を足す。
-- description・checksum・個々の version は返さない。引数は無い。
--
-- 足すだけ (expand)。表への GRANT / REVOKE、ポリシー、ほかの関数には触れない。
-- 形は migration 158 の「6.」の関数と同じ (SECURITY DEFINER + SET search_path = alc_api、
-- PUBLIC から REVOKE し、alc_api_app と alc_api_rt にだけ EXECUTE)。

-- ロックを取れないまま待ち続けないようにする (migration 158 と同じ)。
SET LOCAL lock_timeout = '10s';

CREATE FUNCTION alc_api.migration_status()
RETURNS TABLE (applied bigint, max_version bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = alc_api
AS $$
    SELECT count(*), max(version) FROM alc_api._sqlx_migrations WHERE success
$$;

REVOKE ALL ON FUNCTION alc_api.migration_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.migration_status() TO alc_api_app, alc_api_rt;
