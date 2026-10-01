-- backend を「表の所有者でない実行用ロール」alc_api_rt で繋げるようにする
-- Refs ippoan/alc-app#387
--
-- ---------------------------------------------------------------------------
-- なぜ要るか
-- ---------------------------------------------------------------------------
-- PostgreSQL は、FORCE ROW LEVEL SECURITY の無い表では「表の所有者」にポリシーを適用しない。
-- 本番では migration を流すロール alc_api_app が alc_api の全表の所有者で、backend も同じ
-- alc_api_app で繋いでいる。つまり FORCE の無い表では、backend に RLS が 1 行も掛かっていない
-- (テナントの分離も、migration 153 の dev の軸も)。
-- migration 118〜120・137 のコメントの「alc_api_app は非所有者」は、実物と違う。
--
-- backend だけを、所有者でないロール alc_api_rt で繋ぐ (migration を流すのは alc_api_app のまま)。
-- この migration は、その切り替えの「前」に当てておくもの:
--   * alc_api_rt に、いまの backend が使っている範囲の権限を付ける
--   * 認証前・テナント横断の問い合わせ (いまは所有者なので RLS を素通りしている) を、
--     SECURITY DEFINER 関数として置く
-- 当てただけでは backend の動きは変わらない (接続のロールを替えるのは別の作業)。
--
-- ---------------------------------------------------------------------------
-- 足すだけ (expand)
-- ---------------------------------------------------------------------------
-- 権限・関数を足し、ポリシー 1 本の宛先に alc_api_rt を足すだけ。消すもの・式を変えるものは無い。
-- alc_api_app の権限は何も変えない。
--
-- ---------------------------------------------------------------------------
-- この migration の外で済ませておくもの (本番)
-- ---------------------------------------------------------------------------
-- 本番の alc_api_app は CREATEROLE を持たず、schema alc_api の所有者でもない。したがって
--   * ロール alc_api_rt の作成
--   * GRANT USAGE ON SCHEMA alc_api TO alc_api_rt
-- の 2 つは、権限を持つロールが先に済ませておく。済んでいなければ、下の 1・2 で例外になり
-- migration ごと止まる (黙って飛ばさない。1 transaction なので DB は変わらない)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (DB は無変更でデプロイが止まるだけなので、やり直せる)。
-- SET LOCAL なので、この migration の transaction の中だけに効く。
SET LOCAL lock_timeout = '10s';

-- 1. ロールの存在。
--    無ければ作る (空の DB に 0 から流す環境は superuser が流すので作れる)。
--    作る権限が無い環境で無かった場合は、ここで落とす。「在れば GRANT する」形にはしない
--    (ロールが無いまま通ると、権限の付いていない DB が黙って出来上がる)。
--    ここで作るロールは NOLOGIN。繋ぐための LOGIN とパスワードは migration の外で付ける。
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alc_api_rt') THEN
        BEGIN
            CREATE ROLE alc_api_rt NOLOGIN NOSUPERUSER NOBYPASSRLS NOINHERIT;
        EXCEPTION
        WHEN duplicate_object OR unique_violation THEN
            -- ロールはクラスタ共通。同じクラスタの別の DB へ同時に migration を流すと、
            -- 上の存在確認の後で相手が先に作ることがある。在ればよい (属性は下の 2 で確かめる)。
            NULL;
        WHEN insufficient_privilege THEN
            RAISE EXCEPTION
                'migration 158: ロール alc_api_rt が在りません。この migration を流しているロール (%) には'
                ' ロールを作る権限が無いので、ここでは作れません。'
                ' 権限を持つロールで alc_api_rt (NOSUPERUSER・NOBYPASSRLS・NOINHERIT。% のメンバーにしない) を'
                ' 作ってから再実行してください。',
                current_user, current_user;
        END;
    END IF;
END
$$;

-- 2. 前提の確認 (153 と同じ「沈黙しない」方針)。
--    どれかが違う場合は、黙って穴を残さずここで落とす。
DO $$
DECLARE
    v_super     BOOLEAN;
    v_bypass    BOOLEAN;
    v_count     INT;
    v_found     TEXT[];
BEGIN
    -- (a) superuser / BYPASSRLS だと、RLS がそもそも掛からない。
    SELECT r.rolsuper, r.rolbypassrls
      INTO STRICT v_super, v_bypass
      FROM pg_roles r
     WHERE r.rolname = 'alc_api_rt';

    IF v_super OR v_bypass THEN
        RAISE EXCEPTION
            'migration 158: alc_api_rt が rolsuper = % / rolbypassrls = % です (どちらも false のはず)。'
            ' このロールには RLS が掛かりません。pg_roles を確認し、'
            ' ALTER ROLE alc_api_rt NOSUPERUSER NOBYPASSRLS にしてから再実行してください。',
            v_super, v_bypass;
    END IF;

    -- (b) この migration を流しているロールは、その環境で表を作る = 表の所有者になるロール。
    --     alc_api_rt がそのメンバーだと (NOINHERIT でも SET ROLE で) 所有者の資格を取れてしまい、
    --     RLS が素通りに戻る。
    IF pg_has_role('alc_api_rt', current_user, 'MEMBER') THEN
        RAISE EXCEPTION
            'migration 158: alc_api_rt が、この migration を流しているロール (%) のメンバーです。'
            ' 表の所有者の資格を取れるロールには RLS が掛かりません。'
            ' pg_auth_members を確認し、REVOKE % FROM alc_api_rt をしてから再実行してください。',
            current_user, current_user;
    END IF;

    -- (c) 宛先を絞ったポリシー (TO <role>) は、migration 履歴の上では
    --     tenant_allowed_emails.tenant_isolation (migration 053。宛先 alc_api_app) の 1 本だけ。
    --     下の 5 はこの 1 本の宛先に alc_api_rt を足す。ほかに宛先を絞ったポリシーが
    --     migration 履歴の外で足されていると、その表は alc_api_rt から 1 行も見えなくなるか、
    --     想定と違う見え方になる。
    SELECT count(*),
           coalesce(array_agg(format('%s.%s %s', p.tablename, p.policyname, p.roles::TEXT)
                              ORDER BY p.tablename, p.policyname), '{}')
      INTO v_count, v_found
      FROM pg_policies p
     WHERE p.schemaname = 'alc_api'
       AND p.roles <> '{public}';

    IF v_count <> 1 OR v_found <> ARRAY['tenant_allowed_emails.tenant_isolation {alc_api_app}'] THEN
        RAISE EXCEPTION
            'migration 158: alc_api で宛先を絞ったポリシーが % 本見つかりました: %'
            ' (想定は "tenant_allowed_emails.tenant_isolation {alc_api_app}" の 1 本だけ)。'
            ' migration 履歴の外でポリシーが足された・宛先が変えられた可能性があります。'
            ' pg_policies を確認してから再実行してください。',
            v_count, v_found;
    END IF;

    -- (d) schema の USAGE。持っていなければ付けてみる (schema の所有者が流している環境では通る)。
    --     所有者でないロールが流している環境では付けられない (WARNING か権限エラーになる) ので、
    --     付いたかどうかを確かめ直して、無ければ落とす。
    IF NOT has_schema_privilege('alc_api_rt', 'alc_api', 'USAGE') THEN
        BEGIN
            GRANT USAGE ON SCHEMA alc_api TO alc_api_rt;
        EXCEPTION WHEN insufficient_privilege THEN
            NULL;
        END;

        IF NOT has_schema_privilege('alc_api_rt', 'alc_api', 'USAGE') THEN
            RAISE EXCEPTION
                'migration 158: alc_api_rt が schema alc_api の USAGE を持っていません。'
                ' この migration を流しているロール (%) は schema の所有者でないので、ここでは付けられません。'
                ' schema の所有者で GRANT USAGE ON SCHEMA alc_api TO alc_api_rt をしてから再実行してください。',
                current_user;
        END IF;
    END IF;
END
$$;

-- 3. いま在る表・sequence・関数への権限。
--    表は SELECT / INSERT / UPDATE / DELETE だけ (backend は TRUNCATE・DDL を打たない)。
--    _sqlx_migrations は backend が読まないので外す (schema alc_api に在る環境だけ)。
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA alc_api TO alc_api_rt;

DO $$
BEGIN
    IF to_regclass('alc_api._sqlx_migrations') IS NOT NULL THEN
        REVOKE ALL ON alc_api._sqlx_migrations FROM alc_api_rt;
    END IF;
END
$$;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA alc_api TO alc_api_rt;

--    流しているロールが所有していない関数 (migration 履歴の外で作られたもの) には、
--    ここの GRANT は WARNING を出すだけで付かない。その関数を alc_api_rt が呼べるかどうかは、
--    最後の 7 で確かめる (PUBLIC に EXECUTE が在れば呼べる)。
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA alc_api TO alc_api_rt;

-- 4. これから作る表・sequence・関数への権限。
--    FOR ROLE を書かないので、この migration を流しているロール (= その環境で今後の migration を
--    流し、表を作るロール) が作るものに掛かる。新しい表を作る migration は、alc_api_rt への
--    GRANT を書かなくてよい。
ALTER DEFAULT PRIVILEGES IN SCHEMA alc_api
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO alc_api_rt;
ALTER DEFAULT PRIVILEGES IN SCHEMA alc_api
    GRANT USAGE, SELECT ON SEQUENCES TO alc_api_rt;
ALTER DEFAULT PRIVILEGES IN SCHEMA alc_api
    GRANT EXECUTE ON FUNCTIONS TO alc_api_rt;

-- 5. 宛先を絞ったポリシーに alc_api_rt を足す。
--    TO PUBLIC にはしない (同じ DB に、このアプリのものでないロールが居る)。
--    USING の式 (migration 053) は変えない。
ALTER POLICY tenant_isolation ON alc_api.tenant_allowed_emails TO alc_api_app, alc_api_rt;

-- 6. 認証前・テナント横断の問い合わせを SECURITY DEFINER 関数にする。
--    backend がいま tenant context を立てずに打っている SQL を、そのまま関数に写したもの
--    (列・WHERE・RETURNING は元の SQL と同じ)。新しい入口ではなく、所有者として繋いでいる今
--    できていることを、切り替えの後も同じ範囲でできるようにする。
--    migration 121 (find_user_by_line_user_id)・117 (list_enabled_line_configs) と同じ形。
--
--    全部に共通:
--      * SECURITY DEFINER + SET search_path = alc_api
--      * 引数をそのまま条件に使うだけ (動的 SQL なし)
--      * PUBLIC から REVOKE し、alc_api_app と alc_api_rt にだけ EXECUTE (migration 122 と同じ)
--      * FORCE ROW LEVEL SECURITY の付いた表には触らない (所有者として動いても RLS が掛かるため)

-- Google ログイン中 (テナント未確定) の users の逆引き。google_sub は一意 (migration 047)。
CREATE FUNCTION alc_api.find_user_by_google_sub(p_google_sub TEXT)
RETURNS SETOF alc_api.users
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT * FROM alc_api.users WHERE google_sub = p_google_sub;
$$;
REVOKE ALL ON FUNCTION alc_api.find_user_by_google_sub(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.find_user_by_google_sub(TEXT) TO alc_api_app, alc_api_rt;

-- LINE WORKS ログイン中 (テナント未確定) の users の逆引き。lineworks_id は一意 (migration 047)。
CREATE FUNCTION alc_api.find_user_by_lineworks_id(p_lineworks_id TEXT)
RETURNS SETOF alc_api.users
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT * FROM alc_api.users WHERE lineworks_id = p_lineworks_id;
$$;
REVOKE ALL ON FUNCTION alc_api.find_user_by_lineworks_id(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.find_user_by_lineworks_id(TEXT) TO alc_api_app, alc_api_rt;

-- ログインの最後に refresh token のハッシュと期限を保存する (呼び出し元は user の id しか持たない)。
CREATE FUNCTION alc_api.save_user_refresh_token(
    p_user_id UUID,
    p_token_hash TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    UPDATE alc_api.users
       SET refresh_token_hash = p_token_hash, refresh_token_expires_at = p_expires_at
     WHERE id = p_user_id;
$$;
REVOKE ALL ON FUNCTION alc_api.save_user_refresh_token(UUID, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.save_user_refresh_token(UUID, TEXT, TIMESTAMPTZ) TO alc_api_app, alc_api_rt;

-- 初回ログイン中 (テナント未確定) の招待の逆引き。email は一意 (migration 053)。
CREATE FUNCTION alc_api.find_invitation_by_email(p_email TEXT)
RETURNS SETOF alc_api.tenant_allowed_emails
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT * FROM alc_api.tenant_allowed_emails WHERE email = p_email;
$$;
REVOKE ALL ON FUNCTION alc_api.find_invitation_by_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.find_invitation_by_email(TEXT) TO alc_api_app, alc_api_rt;

-- 全テナントの、FCM token を持つ有効な端末 (着信の通知を送る内部の口が使う)。
CREATE FUNCTION alc_api.list_fcm_devices()
RETURNS TABLE(
    id UUID,
    fcm_token TEXT,
    call_enabled BOOLEAN,
    call_schedule JSONB
)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT d.id, d.fcm_token, d.call_enabled, d.call_schedule
      FROM alc_api.devices d
     WHERE d.fcm_token IS NOT NULL AND d.status = 'active';
$$;
REVOKE ALL ON FUNCTION alc_api.list_fcm_devices() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_fcm_devices() TO alc_api_app, alc_api_rt;

-- 全テナントの、着信を受ける設定の有効な端末。
-- list_fcm_devices とは返す列も条件も違う (device_name を返し、call_enabled = true で絞る) ので別の関数。
CREATE FUNCTION alc_api.list_all_callable_devices()
RETURNS TABLE(
    id UUID,
    device_name TEXT,
    fcm_token TEXT
)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT d.id, d.device_name, d.fcm_token
      FROM alc_api.devices d
     WHERE d.status = 'active' AND d.fcm_token IS NOT NULL AND d.call_enabled = true;
$$;
REVOKE ALL ON FUNCTION alc_api.list_all_callable_devices() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_all_callable_devices() TO alc_api_app, alc_api_rt;

-- 開発用の端末 (FCM token 有り・有効) を持つテナントの id。
CREATE FUNCTION alc_api.list_dev_device_tenant_ids()
RETURNS SETOF UUID
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT DISTINCT d.tenant_id
      FROM alc_api.devices d
     WHERE d.status = 'active' AND d.is_dev_device = true AND d.fcm_token IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION alc_api.list_dev_device_tenant_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_dev_device_tenant_ids() TO alc_api_app, alc_api_rt;

-- 全テナントの、点呼の超過を通知する有効な webhook の設定 (定期のバッチが使う)。
CREATE FUNCTION alc_api.list_tenko_overdue_webhook_configs()
RETURNS SETOF alc_api.webhook_configs
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT * FROM alc_api.webhook_configs WHERE event_type = 'tenko_overdue' AND enabled = TRUE;
$$;
REVOKE ALL ON FUNCTION alc_api.list_tenko_overdue_webhook_configs() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_tenko_overdue_webhook_configs() TO alc_api_app, alc_api_rt;

-- テナントへの参加の申請を作る。申請先は申請者自身のテナントではないので、
-- 申請者の tenant context では書けない。
CREATE FUNCTION alc_api.create_access_request(p_tenant_id UUID, p_user_id UUID)
RETURNS SETOF alc_api.access_requests
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    INSERT INTO alc_api.access_requests (tenant_id, user_id)
    VALUES (p_tenant_id, p_user_id) RETURNING *;
$$;
REVOKE ALL ON FUNCTION alc_api.create_access_request(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.create_access_request(UUID, UUID) TO alc_api_app, alc_api_rt;

-- 7. 権限が揃ったことを確かめる。
--    GRANT は、流しているロールが所有していない対象には WARNING を出すだけで通ってしまう。
--    付いていないものが 1 つでも在れば落とす (切り替えた後に backend が権限エラーになるのを、
--    ここで先に見つける)。関数は PUBLIC 経由の EXECUTE でもよい。
DO $$
DECLARE
    v_missing TEXT[];
BEGIN
    SELECT coalesce(array_agg(m.what ORDER BY m.what), '{}')
      INTO v_missing
      FROM (
        SELECT 'schema alc_api: USAGE' AS what
         WHERE NOT has_schema_privilege('alc_api_rt', 'alc_api', 'USAGE')

        UNION ALL
        SELECT format('table %s: %s', c.relname, p.priv)
          FROM pg_class c
         CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) AS p(priv)
         WHERE c.relnamespace = 'alc_api'::regnamespace
           AND c.relkind IN ('r', 'p')
           AND c.relname <> '_sqlx_migrations'
           AND NOT has_table_privilege('alc_api_rt', c.oid, p.priv)

        UNION ALL
        SELECT format('sequence %s: USAGE', c.relname)
          FROM pg_class c
         WHERE c.relnamespace = 'alc_api'::regnamespace
           -- CASE で包む: 条件の評価順は決まっておらず、sequence でない行に
           -- has_sequence_privilege が当たるとエラーになる
           AND CASE WHEN c.relkind = 'S'
                    THEN NOT has_sequence_privilege('alc_api_rt', c.oid, 'USAGE')
                    ELSE false
               END

        UNION ALL
        SELECT format('function %s: EXECUTE', f.oid::regprocedure)
          FROM pg_proc f
         WHERE f.pronamespace = 'alc_api'::regnamespace
           AND f.prosecdef
           AND NOT has_function_privilege('alc_api_rt', f.oid, 'EXECUTE')
      ) m;

    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION
            'migration 158: alc_api_rt に付いていない権限が % 件あります: %。'
            ' この migration を流しているロール (%) が所有していない対象には、ここからは GRANT できません。'
            ' その対象の所有者で alc_api_rt に GRANT してから再実行してください。',
            cardinality(v_missing), v_missing, current_user;
    END IF;
END
$$;
