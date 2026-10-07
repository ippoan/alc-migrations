-- RLS が「書いただけ」で終わっていないことを確かめる不変条件の検査 (migration 158〜)。
-- このファイルは 1 文の SELECT 1 本。crate に含まれ、backend が同じ 1 文を流す
-- (alc_migrations::RLS_INVARIANTS_QUERY)。ci/ のうち crate に入るのはこのファイルと rls_state.sql と
-- expected_rls_state.json の 3 本だけ。
-- 検査を足す・番号を変えるときは src/lib.rs の RLS_INVARIANT_CHECKS も直す (tests が一致を見る)。
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
--   6. alc_api schema に view / materialized view が無い
--      (view は所有者の権限で表を読むので、RLS の迂回路になる。許可リストなし)
--   7. SECURITY DEFINER の関数は、search_path が固定で (proconfig に search_path= が在る)、
--      PUBLIC が EXECUTE できない。PUBLIC の側だけ、下の許可リストの関数を除く
--      (search_path の側に許可リストは無い)
--   8. RLS 有効の表に、USING か WITH CHECK の式が true そのものの permissive なポリシーが無い
--      (全行を通す)。下の許可リストの (表, command) を除く
--   9. RLS 有効の表に、式の COALESCE の最後の引数が列 tenant_id そのものの permissive なポリシーが無い
--      (tenant_id = COALESCE(<テナントの設定>, tenant_id) は、テナント未設定の接続で tenant_id = tenant_id になり
--      全行を通す)。許可リストなし。★ 捕まえるのはこの 1 つの綴りだけ。テナント未設定で全行を通す形を
--      全部は捕まえない (COALESCE(…, (SELECT …)) や OR current_setting(…) IS NULL などは別の綴りで、捕まえない)
--
-- RLS を無効のままにしてよい表 (検査 3 の許可リスト)。足すときは、ここに理由を書く:
--   * tenants                 — テナントの一覧そのもの。ログイン中 (テナント未確定) に slug / ドメインで引く
--   * _sqlx_migrations        — sqlx の適用履歴。alc_api_rt には権限を付けない (migration 158)
--   * vehicle_settings_dumps  — 車輛の設定の dump の索引 (migration 110)。RLS を有効にしないまま作られた。
--                               有効にするのは別の migration で扱う (ここでは、いまの状態を固定するだけ)
--
-- PUBLIC が EXECUTE できてよい SECURITY DEFINER の関数 (検査 7 の許可リスト。関数の名前で 21 本)。
-- migration 158 より前に作られ、PUBLIC の EXECUTE が残っている (PostgreSQL は新しい関数の EXECUTE を
-- 既定で PUBLIC に付ける)。外す (REVOKE して必要なロールにだけ GRANT する) のは別の migration で扱う。
-- ここに足さない — 新しい SECURITY DEFINER の関数は 158 の形 (PUBLIC から REVOKE) で作る。
-- 括弧の中は、その関数が最初に出てくる migration:
--   * archive_delete_dtako_date / archive_fetch_dtako_rows_json / archive_list_dtako_dates /
--     archive_list_old_dtako_dates / archive_upsert_dtako_batch (084)
--   * close_dtako_ticket_by_token (115)
--   * find_recipient_by_line_user_id (076)
--   * find_user_by_line_user_id (121)
--   * get_device_settings_by_id / lookup_device_tenant (063)
--   * get_trouble_schedule (088)
--   * list_enabled_line_configs (117)
--   * lookup_bot_config_for_webhook (102)
--   * lookup_delivery_for_view (107)
--   * lookup_line_config_by_channel (072)
--   * lookup_lineworks_channel_for_send (129)
--   * lookup_notify_recipient_for_send (130)
--   * mark_delivery_read (071)
--   * set_current_tenant (004)
--   * verify_device_token (116)
--   * resolve_sso_config — migration の履歴に無い (テスト用 DB では scripts/init_local_db.sql が作る)
--
-- 式が true のポリシーを持ってよい (表, command) (検査 8 の許可リスト)。理由は migration のコメントのまま。
-- 式を絞るのは別の migration で扱う (ここでは、いまの状態を固定するだけ)。ここに足さない:
--   * tenko_call_numbers / SELECT            — migration 032「マスタは認証前に参照するため SELECT は全行許可」
--   * tenko_call_drivers / SELECT            — migration 032「phone_number 検索は set_config 前のため SELECT 許可」
--   * device_registration_requests / SELECT  — migration 035「ポーリング用に SELECT は公開
--                                              (registration_code でフィルタされる)」
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

    UNION ALL
    SELECT 6, 'view ' || c.relname,
           format('alc_api schema に %s が在る (所有者の権限で表を読むので、RLS の迂回路になる)',
                  CASE c.relkind WHEN 'm' THEN 'materialized view' ELSE 'view' END)
      FROM pg_class c
     WHERE c.relnamespace = 'alc_api'::regnamespace
       AND c.relkind IN ('v', 'm')

    UNION ALL
    SELECT 7, 'function ' || f.oid::regprocedure,
           'SECURITY DEFINER なのに search_path が固定されていない (proconfig に search_path= が無い)'
      FROM pg_proc f
     WHERE f.pronamespace = 'alc_api'::regnamespace
       AND f.prosecdef
       AND NOT EXISTS (
           SELECT 1
             FROM unnest(f.proconfig) AS cfg(item)
            WHERE cfg.item LIKE 'search_path=%'
       )

    UNION ALL
    SELECT 7, 'function ' || f.oid::regprocedure,
           'SECURITY DEFINER の関数を PUBLIC が EXECUTE でき、許可リストにも無い'
      FROM pg_proc f
     WHERE f.pronamespace = 'alc_api'::regnamespace
       AND f.prosecdef
       AND has_function_privilege('public', f.oid, 'EXECUTE')
       AND f.proname NOT IN (
           'archive_delete_dtako_date', 'archive_fetch_dtako_rows_json', 'archive_list_dtako_dates',
           'archive_list_old_dtako_dates', 'archive_upsert_dtako_batch', 'close_dtako_ticket_by_token',
           'find_recipient_by_line_user_id', 'find_user_by_line_user_id', 'get_device_settings_by_id',
           'get_trouble_schedule', 'list_enabled_line_configs', 'lookup_bot_config_for_webhook',
           'lookup_delivery_for_view', 'lookup_device_tenant', 'lookup_line_config_by_channel',
           'lookup_lineworks_channel_for_send', 'lookup_notify_recipient_for_send', 'mark_delivery_read',
           'resolve_sso_config', 'set_current_tenant', 'verify_device_token')

    UNION ALL
    SELECT 8, 'table ' || t.relname,
           format('ポリシー %s (%s) の %s の式が true (全行を通す) で、許可リストにも無い',
                  p.policyname, p.cmd,
                  CASE WHEN p.qual = 'true' AND p.with_check = 'true' THEN 'USING と WITH CHECK'
                       WHEN p.qual = 'true' THEN 'USING'
                       ELSE 'WITH CHECK'
                  END)
      FROM tbl t
      JOIN pg_policies p
        ON p.schemaname = 'alc_api'
       AND p.tablename = t.relname
     WHERE t.relrowsecurity
       AND p.permissive = 'PERMISSIVE'
       AND (p.qual = 'true' OR p.with_check = 'true')
       AND (t.relname::text, p.cmd) NOT IN (
           ('tenko_call_numbers', 'SELECT'),
           ('tenko_call_drivers', 'SELECT'),
           ('device_registration_requests', 'SELECT'))

    UNION ALL
    -- 検査 9: pg_policies.qual / with_check (PostgreSQL が式を組み立て直した文字列) の中の
    -- COALESCE( … , tenant_id ) の形。この綴りだけを捕まえる
    SELECT 9, 'table ' || t.relname,
           format('ポリシー %s (%s) の %s の式の COALESCE の最後の引数が列 tenant_id そのもの (テナント未設定で全行を通す)',
                  p.policyname, p.cmd,
                  CASE WHEN p.qual ~ 'COALESCE\(.*,\s*(\w+\.)?tenant_id\s*\)'
                        AND p.with_check ~ 'COALESCE\(.*,\s*(\w+\.)?tenant_id\s*\)' THEN 'USING と WITH CHECK'
                       WHEN p.qual ~ 'COALESCE\(.*,\s*(\w+\.)?tenant_id\s*\)' THEN 'USING'
                       ELSE 'WITH CHECK'
                  END)
      FROM tbl t
      JOIN pg_policies p
        ON p.schemaname = 'alc_api'
       AND p.tablename = t.relname
     WHERE t.relrowsecurity
       AND p.permissive = 'PERMISSIVE'
       AND (p.qual ~ 'COALESCE\(.*,\s*(\w+\.)?tenant_id\s*\)'
            OR p.with_check ~ 'COALESCE\(.*,\s*(\w+\.)?tenant_id\s*\)')
)
SELECT v.check_no, v.object, v.detail
  FROM violation v
 ORDER BY v.check_no, v.object, v.detail;
