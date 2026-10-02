-- alc_api schema の RLS まわりの「いまの状態」を、カタログから読んで 1 つの JSON で返す (Refs ippoan/auth-worker#605)。
-- このファイルは 1 文の SELECT 1 本 (1 行・1 列 state jsonb)。crate に含まれ、backend が同じ 1 文を流す
-- (alc_migrations::RLS_STATE_QUERY)。
--
-- 合否は決めない。合否を決めるのは check_rls_invariants.sql だけで、こちらは、その検査が見た DB が
-- 実際にどうだったかを、読む人が自分で確かめ直すための材料。
--
--   psql -v ON_ERROR_STOP=1 -At -f ci/rls_state.sql
--
-- 返す形:
--   table_count                 — 表 (検査 SQL の tbl と同じ定義) の総数
--   tables                      — 状態が同じ表をまとめた組。count の降順 → 先頭の表名の昇順。count の合計 = table_count
--     count / names             — 組の表の数と名前 (昇順)
--     rls_enabled / rls_forced  — ROW LEVEL SECURITY が有効か、FORCE が付いているか
--     owner                     — 表の所有者
--     runtime_role_can_act_as_owner — alc_api_rt が所有者の資格を取れるか (検査 1 と同じ判定)
--     policies                  — ポリシーの配列 (command / permissive / roles / using / with_check)。
--                                 名前は入れない (表ごとに違うので、入れると組にまとまらない)
--     runtime_role_privileges   — alc_api_rt が持つ SELECT / INSERT / UPDATE / DELETE
--   views                       — view / materialized view の名前
--   security_definer_functions  — SECURITY DEFINER の関数 (signature / search_path /
--                                 runtime_role_can_execute / public_can_execute)
--   sequences                   — sequence の数 (count) と、alc_api_rt に USAGE が無いものの名前
--                                 (runtime_role_usage_missing)
--
-- ロール alc_api_rt が無い DB でもエラーにしない。ロールに依る値 (runtime_role_ で始まる key) は
-- null で返す (検査 0 が違反を出す場面で、こちらが落ちて検査の結果ごと失われないように)。
--
-- カタログを読む SELECT 1 文だけで、表の行は読まず、何も変更しない。SET ROLE も使わないので、
-- 本番でもそのまま流せる (どのロールで流しても同じ結果になる)。
-- ポリシーの式と関数の signature の schema 修飾は、接続の search_path に依る (PostgreSQL が
-- search_path に在る schema を省く)。
-- 配列の並びは全部 ORDER BY で固定してある (文字列は COLLATE "C")。足すときも必ず付ける。
-- psql -f でも、driver の prepared statement でも流せる形を保つ: 文は 1 つだけ、psql の
-- メタコマンドと変数は使わない、コメントは行コメントだけ。

WITH rt AS (
    SELECT r.oid
      FROM pg_roles r
     WHERE r.rolname = 'alc_api_rt'
), tbl AS (
    SELECT c.oid, c.relname::text AS name, c.relowner, c.relrowsecurity, c.relforcerowsecurity
      FROM pg_class c
     WHERE c.relnamespace = 'alc_api'::regnamespace
       AND c.relkind IN ('r', 'p')
), tbl_state AS (
    SELECT t.name,
           t.relrowsecurity AS rls_enabled,
           t.relforcerowsecurity AS rls_forced,
           t.relowner::regrole::text AS owner,
           -- rt が無ければ rt.oid は NULL で、権限の関数は NULL を返す (エラーにならない)
           pg_has_role(rt.oid, t.relowner, 'MEMBER') AS runtime_role_can_act_as_owner,
           COALESCE((
               SELECT jsonb_agg(
                          jsonb_build_object(
                              'command', p.cmd,
                              'permissive', p.permissive = 'PERMISSIVE',
                              'roles', to_jsonb(r.sorted),
                              'using', p.qual,
                              'with_check', p.with_check)
                          ORDER BY p.cmd COLLATE "C", p.qual COLLATE "C", p.with_check COLLATE "C", r.sorted)
                 FROM pg_policies p
                CROSS JOIN LATERAL (
                          SELECT array_agg(x.role_name ORDER BY x.role_name COLLATE "C") AS sorted
                            FROM unnest(p.roles::text[]) AS x(role_name)
                      ) r
                WHERE p.schemaname = 'alc_api'
                  AND p.tablename = t.name
           ), '[]'::jsonb) AS policies,
           CASE WHEN rt.oid IS NOT NULL THEN COALESCE((
               SELECT jsonb_agg(v.priv ORDER BY v.ord)
                 FROM (VALUES (1, 'SELECT'), (2, 'INSERT'), (3, 'UPDATE'), (4, 'DELETE')) AS v(ord, priv)
                WHERE has_table_privilege(rt.oid, t.oid, v.priv)
           ), '[]'::jsonb) END AS runtime_role_privileges
      FROM tbl t
      LEFT JOIN rt ON true
), grp AS (
    SELECT s.rls_enabled, s.rls_forced, s.owner, s.runtime_role_can_act_as_owner,
           s.policies, s.runtime_role_privileges,
           count(*) AS table_count,
           jsonb_agg(s.name ORDER BY s.name COLLATE "C") AS names,
           min(s.name COLLATE "C") AS first_name
      FROM tbl_state s
     GROUP BY s.rls_enabled, s.rls_forced, s.owner, s.runtime_role_can_act_as_owner,
              s.policies, s.runtime_role_privileges
)
SELECT jsonb_build_object(
    'table_count', (SELECT count(*) FROM tbl),
    'tables', COALESCE((
        SELECT jsonb_agg(
                   jsonb_build_object(
                       'count', g.table_count,
                       'rls_enabled', g.rls_enabled,
                       'rls_forced', g.rls_forced,
                       'owner', g.owner,
                       'runtime_role_can_act_as_owner', g.runtime_role_can_act_as_owner,
                       'policies', g.policies,
                       'runtime_role_privileges', g.runtime_role_privileges,
                       'names', g.names)
                   ORDER BY g.table_count DESC, g.first_name COLLATE "C")
          FROM grp g
    ), '[]'::jsonb),
    'views', COALESCE((
        SELECT jsonb_agg(c.relname::text ORDER BY c.relname::text COLLATE "C")
          FROM pg_class c
         WHERE c.relnamespace = 'alc_api'::regnamespace
           AND c.relkind IN ('v', 'm')
    ), '[]'::jsonb),
    'security_definer_functions', COALESCE((
        SELECT jsonb_agg(
                   jsonb_build_object(
                       'signature', f.oid::regprocedure::text,
                       'search_path', (
                           SELECT substr(cfg.item, length('search_path=') + 1)
                             FROM unnest(f.proconfig) AS cfg(item)
                            WHERE cfg.item LIKE 'search_path=%'
                       ),
                       'runtime_role_can_execute', has_function_privilege(rt.oid, f.oid, 'EXECUTE'),
                       'public_can_execute', has_function_privilege('public', f.oid, 'EXECUTE'))
                   ORDER BY f.oid::regprocedure::text COLLATE "C")
          FROM pg_proc f
          LEFT JOIN rt ON true
         WHERE f.pronamespace = 'alc_api'::regnamespace
           AND f.prosecdef
    ), '[]'::jsonb),
    'sequences', (
        -- has_sequence_privilege は sequence でない行に当たるとエラーになる。FILTER は WHERE
        -- (relkind = 'S') を通った行にだけ評価されるので、当たらない
        SELECT jsonb_build_object(
                   'count', count(*),
                   'runtime_role_usage_missing',
                   CASE WHEN EXISTS (SELECT 1 FROM rt) THEN COALESCE(
                       jsonb_agg(c.relname::text ORDER BY c.relname::text COLLATE "C")
                           FILTER (WHERE NOT has_sequence_privilege(rt.oid, c.oid, 'USAGE')),
                       '[]'::jsonb) END)
          FROM pg_class c
          LEFT JOIN rt ON true
         WHERE c.relnamespace = 'alc_api'::regnamespace
           AND c.relkind = 'S'
    )
) AS state;
