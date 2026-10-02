-- RLS が「書いただけ」で終わっていないことを確かめる不変条件の検査 (migration 158〜)。
-- このファイルは 1 文の SELECT 1 本。crate に含まれ、backend が同じ 1 文を流す
-- (alc_migrations::RLS_INVARIANTS_QUERY)。ci/ のうち crate に入るのはこのファイルだけ。
--
-- backend は実行用ロール alc_api_rt で繋ぐ。ポリシーを書いても、次のどれかに当たると
-- backend には効かない。違反を 1 行ずつ返す (check_no int, object text, detail text)。
-- 0 行なら合格。CI の replay job が、全 migration を流した後の DB にこれを流し、
-- 1 行でも返れば落とす。
--
--   psql -v ON_ERROR_STOP=1 -At -f ci/check_rls_invariants.sql
--
-- 検査:
--   0. ロール alc_api_rt が在る
--   1. RLS 有効の表で、alc_api_rt が所有者の資格を取れない (所有者でも、所有者のメンバーでもない)。
--      取れる場合は FORCE ROW LEVEL SECURITY が付いている
--      (PostgreSQL は FORCE の無い表では所有者にポリシーを適用しない)
--   2. RLS 有効の表が、alc_api_rt に効くポリシーを 1 本以上持つ
--      (宛先が PUBLIC か、alc_api_rt を含む。効くポリシーが無い表は 1 行も読み書きできない)
--   3. RLS が無効の表は、下の許可リストに在るものだけ
--   4. alc_api_rt が superuser でも BYPASSRLS でもない
--   5. alc_api_rt が schema の USAGE、全表 (_sqlx_migrations を除く) の SELECT / INSERT / UPDATE / DELETE、
--      全 sequence の USAGE、SECURITY DEFINER の全関数の EXECUTE を持つ
--
-- RLS を無効のままにしてよい表 (検査 3 の許可リスト)。足すときは、ここに理由を書く:
--   * tenants                 — テナントの一覧そのもの。ログイン中 (テナント未確定) に slug / ドメインで引く
--   * _sqlx_migrations        — sqlx の適用履歴。alc_api_rt には権限を付けない (migration 158)
--   * vehicle_settings_dumps  — 車輛の設定の dump の索引 (migration 110)。RLS を有効にしないまま作られた。
--                               有効にするのは別の migration で扱う (ここでは、いまの状態を固定するだけ)
--
-- カタログを読む SELECT 1 文だけで、何も変更しない。SET ROLE も使わないので、本番でもそのまま
-- 流せる (どのロールで流しても同じ結果になる)。
-- psql -f でも、driver の prepared statement でも流せる形を保つ: 文は 1 つだけ、psql の
-- メタコマンドと変数は使わない、コメントは行コメントだけ。

WITH rt AS (
    SELECT r.oid, r.rolsuper, r.rolbypassrls
      FROM pg_roles r
     WHERE r.rolname = 'alc_api_rt'
), tbl AS (
    SELECT c.oid, c.relname, c.relowner, c.relrowsecurity, c.relforcerowsecurity
      FROM pg_class c
     WHERE c.relnamespace = 'alc_api'::regnamespace
       AND c.relkind IN ('r', 'p')
), violation(check_no, object, detail) AS (
    SELECT 0, 'role alc_api_rt', 'ロールが在りません'
     WHERE NOT EXISTS (SELECT 1 FROM rt)

    UNION ALL
    SELECT 1, 'table ' || t.relname,
           format('alc_api_rt が所有者 (%s) の資格を取れ、FORCE ROW LEVEL SECURITY も無い = ポリシーが掛からない',
                  t.relowner::regrole)
      FROM tbl t, rt
     WHERE t.relrowsecurity
       AND NOT t.relforcerowsecurity
       AND pg_has_role(rt.oid, t.relowner, 'MEMBER')

    UNION ALL
    SELECT 2, 'table ' || t.relname,
           'RLS は有効だが、alc_api_rt に効くポリシー (宛先が PUBLIC か alc_api_rt を含む) が 1 本も無い'
      FROM tbl t, rt
     WHERE t.relrowsecurity
       AND NOT EXISTS (
           SELECT 1
             FROM pg_policy p
            WHERE p.polrelid = t.oid
              AND (p.polroles = '{0}'::oid[] OR rt.oid = ANY (p.polroles))
       )

    UNION ALL
    SELECT 3, 'table ' || t.relname,
           'RLS が無効で、許可リスト (tenants / _sqlx_migrations / vehicle_settings_dumps) にも無い'
      FROM tbl t
     WHERE NOT t.relrowsecurity
       AND t.relname NOT IN ('tenants', '_sqlx_migrations', 'vehicle_settings_dumps')

    UNION ALL
    SELECT 4, 'role alc_api_rt',
           format('rolsuper = %s / rolbypassrls = %s (どちらも false のはず)', rt.rolsuper, rt.rolbypassrls)
      FROM rt
     WHERE rt.rolsuper OR rt.rolbypassrls

    UNION ALL
    SELECT 5, 'schema alc_api', 'alc_api_rt に USAGE が無い'
      FROM rt
     WHERE NOT has_schema_privilege(rt.oid, 'alc_api', 'USAGE')

    UNION ALL
    SELECT 5, 'table ' || t.relname, format('alc_api_rt に %s が無い', p.priv)
      FROM tbl t
     CROSS JOIN rt
     CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) AS p(priv)
     WHERE t.relname <> '_sqlx_migrations'
       AND NOT has_table_privilege(rt.oid, t.oid, p.priv)

    UNION ALL
    SELECT 5, 'sequence ' || c.relname, 'alc_api_rt に USAGE が無い'
      FROM pg_class c, rt
     WHERE c.relnamespace = 'alc_api'::regnamespace
       -- CASE で包む: 条件の評価順は決まっておらず、sequence でない行に
       -- has_sequence_privilege が当たるとエラーになる
       AND CASE WHEN c.relkind = 'S'
                THEN NOT has_sequence_privilege(rt.oid, c.oid, 'USAGE')
                ELSE false
           END

    UNION ALL
    SELECT 5, 'function ' || f.oid::regprocedure, 'alc_api_rt に EXECUTE が無い (SECURITY DEFINER)'
      FROM pg_proc f, rt
     WHERE f.pronamespace = 'alc_api'::regnamespace
       AND f.prosecdef
       AND NOT has_function_privilege(rt.oid, f.oid, 'EXECUTE')
)
SELECT v.check_no, v.object, v.detail
  FROM violation v
 ORDER BY v.check_no, v.object, v.detail;
