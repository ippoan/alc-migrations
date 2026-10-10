-- CI の replay job 専用の検査 (migration 158・160)。crate には含めない (scripts/ ではなく ci/ に置く)。
--
-- init → 全 migration → grants を流した後の DB に対して、実行用ロール alc_api_rt で
--   * 認証前・テナント横断の SECURITY DEFINER 関数 11 本を、tenant context 無しで呼べる
--   * 適用履歴の件数と最大 version を関数 (160) で読める。_sqlx_migrations の直読みはできない
--   * 同じ問い合わせを表へ直接打つと、RLS が掛かる (エラーか 0 行)
--   * tenant_allowed_emails のポリシー (宛先を絞ってある) が alc_api_rt に効く
-- ことを確かめる。alc_api_rt はどちらの軸 (表の所有者が postgres / alc_api_app) でも所有者でない。
-- 全体を 1 transaction で流して最後に ROLLBACK するので、DB には何も残らない。
-- id はその場で作る (実在の tenant_id / メールアドレスは書かない)。
--
--   psql -v ON_ERROR_STOP=1 -f ci/check_runtime_role.sql
--
-- どれか 1 つでも期待と違えば例外で止まる (psql の終了コードが 0 でなくなる)。

\set ON_ERROR_STOP on
SET plpgsql.check_asserts = on;

BEGIN;

-- ---------------------------------------------------------------------------
-- 準備 (superuser)。2 つのテナントに、関数が拾う行を 1 つずつ作る
-- ---------------------------------------------------------------------------
SELECT set_config('chk.tenant_a', gen_random_uuid()::TEXT, false),
       set_config('chk.tenant_b', gen_random_uuid()::TEXT, false),
       set_config('chk.key', 'chk-' || gen_random_uuid()::TEXT, false) \gset chk_

INSERT INTO alc_api.tenants (id, name)
VALUES (current_setting('chk.tenant_a')::UUID, 'ci check a'),
       (current_setting('chk.tenant_b')::UUID, 'ci check b');

-- users: テナント a に Google の利用者、テナント b に LINE WORKS の利用者
WITH g AS (
    INSERT INTO alc_api.users (tenant_id, google_sub, email, name)
    VALUES (current_setting('chk.tenant_a')::UUID, current_setting('chk.key') || '-g',
            current_setting('chk.key') || '-g@example.invalid', 'ci check')
    RETURNING id
), l AS (
    INSERT INTO alc_api.users (tenant_id, lineworks_id, email, name)
    VALUES (current_setting('chk.tenant_b')::UUID, current_setting('chk.key') || '-l',
            current_setting('chk.key') || '-l@example.invalid', 'ci check')
    RETURNING id
)
SELECT set_config('chk.user_g', g.id::TEXT, false),
       set_config('chk.user_l', l.id::TEXT, false)
  FROM g, l \gset chk_

-- 招待: テナント b
INSERT INTO alc_api.tenant_allowed_emails (tenant_id, email)
VALUES (current_setting('chk.tenant_b')::UUID, current_setting('chk.key') || '-inv@example.invalid');

-- 端末: テナント a に「着信を受ける」端末、テナント b に開発用の端末 (どちらも FCM token 有り・有効)
INSERT INTO alc_api.devices (tenant_id, device_name, fcm_token, call_enabled, is_dev_device)
VALUES (current_setting('chk.tenant_a')::UUID, current_setting('chk.key') || '-call', 'ci-check-token', true, false),
       (current_setting('chk.tenant_b')::UUID, current_setting('chk.key') || '-dev', 'ci-check-token', false, true);

-- webhook: 両方のテナントに点呼の超過の設定 (b は無効)
INSERT INTO alc_api.webhook_configs (tenant_id, event_type, url, enabled)
VALUES (current_setting('chk.tenant_a')::UUID, 'tenko_overdue', 'https://example.invalid/', TRUE),
       (current_setting('chk.tenant_b')::UUID, 'tenko_overdue', 'https://example.invalid/', FALSE);

-- 勤怠申請の設定 (163): テナント a は受付中、テナント b は無効
INSERT INTO alc_api.leave_settings (tenant_id, mailbox, allowed_senders, enabled)
VALUES (current_setting('chk.tenant_a')::UUID, 'chk-' || substr(md5(current_setting('chk.key')), 1, 12),
        ARRAY['sender@example.invalid'], TRUE),
       (current_setting('chk.tenant_b')::UUID, 'chk-' || substr(md5(current_setting('chk.key') || 'b'), 1, 12),
        '{}', FALSE);

-- 権限を何も付けていないロール (PUBLIC からの REVOKE の確認用)
CREATE ROLE chk_nobody NOLOGIN;

-- ---------------------------------------------------------------------------
-- ここから実行用ロール (所有者でない・NOBYPASSRLS)。tenant context は立てない
-- ---------------------------------------------------------------------------
SET ROLE alc_api_rt;

-- 1. 11 本の関数を、tenant context 無しで呼べる。返す行は元の SQL と同じ範囲。
DO $$
DECLARE
    v_key      CONSTANT TEXT := current_setting('chk.key');
    v_tenant_a CONSTANT UUID := current_setting('chk.tenant_a')::UUID;
    v_tenant_b CONSTANT UUID := current_setting('chk.tenant_b')::UUID;
    v_user_g   CONSTANT UUID := current_setting('chk.user_g')::UUID;
    v_user_l   CONSTANT UUID := current_setting('chk.user_l')::UUID;
    v_expires  CONSTANT TIMESTAMPTZ := now() + interval '1 day';
    v_user     alc_api.users;
    v_inv      alc_api.tenant_allowed_emails;
    v_req      alc_api.access_requests;
    v_leave    RECORD;
    v_tenants  UUID[];
    v_count    BIGINT;
BEGIN
    ASSERT current_setting('app.current_tenant_id', true) IS NULL,
        '1: 新しい接続なのに app.current_tenant_id が設定済み';

    -- find_user_by_google_sub / find_user_by_lineworks_id
    SELECT * INTO STRICT v_user FROM alc_api.find_user_by_google_sub(v_key || '-g');
    ASSERT v_user.id = v_user_g AND v_user.tenant_id = v_tenant_a, '1: find_user_by_google_sub が違う行を返した';
    SELECT count(*) INTO v_count FROM alc_api.find_user_by_google_sub(v_key || '-none');
    ASSERT v_count = 0, '1: find_user_by_google_sub が、在るはずのない行を返した';

    SELECT * INTO STRICT v_user FROM alc_api.find_user_by_lineworks_id(v_key || '-l');
    ASSERT v_user.id = v_user_l AND v_user.tenant_id = v_tenant_b, '1: find_user_by_lineworks_id が違う行を返した';

    -- save_user_refresh_token: 指定した利用者だけが書き換わる
    PERFORM alc_api.save_user_refresh_token(v_user_g, 'ci-check-hash', v_expires);
    SELECT * INTO STRICT v_user FROM alc_api.find_user_by_google_sub(v_key || '-g');
    ASSERT v_user.refresh_token_hash = 'ci-check-hash' AND v_user.refresh_token_expires_at = v_expires,
        '1: save_user_refresh_token が保存していない';
    SELECT * INTO STRICT v_user FROM alc_api.find_user_by_lineworks_id(v_key || '-l');
    ASSERT v_user.refresh_token_hash IS NULL, '1: save_user_refresh_token が別の利用者を書き換えた';

    -- find_invitation_by_email
    SELECT * INTO STRICT v_inv FROM alc_api.find_invitation_by_email(v_key || '-inv@example.invalid');
    ASSERT v_inv.tenant_id = v_tenant_b, '1: find_invitation_by_email が違う行を返した';

    -- list_fcm_devices: 両方のテナントの端末が出る
    SELECT count(*) INTO v_count FROM alc_api.list_fcm_devices() d
      JOIN alc_api.get_device_re_pair_state(d.id) s ON s.tenant_id IN (v_tenant_a, v_tenant_b);
    ASSERT v_count = 2, format('1: list_fcm_devices が返した検査用の端末が %s 台 (2 台のはず)', v_count);

    -- list_all_callable_devices: 着信を受ける設定の端末だけ
    SELECT count(*) INTO v_count FROM alc_api.list_all_callable_devices() d WHERE d.device_name LIKE v_key || '-%';
    ASSERT v_count = 1, format('1: list_all_callable_devices が返した検査用の端末が %s 台 (1 台のはず)', v_count);

    -- list_dev_device_tenant_ids: 開発用の端末を持つテナントだけ
    SELECT count(*) INTO v_count FROM alc_api.list_dev_device_tenant_ids() t WHERE t IN (v_tenant_a, v_tenant_b);
    ASSERT v_count = 1, format('1: list_dev_device_tenant_ids が返した検査用のテナントが %s 件 (1 件のはず)', v_count);
    ASSERT EXISTS (SELECT 1 FROM alc_api.list_dev_device_tenant_ids() t WHERE t = v_tenant_b),
        '1: list_dev_device_tenant_ids が開発用の端末を持つテナントを返していない';

    -- list_tenko_overdue_webhook_configs: 有効な設定だけ
    SELECT count(*) INTO v_count FROM alc_api.list_tenko_overdue_webhook_configs() w
     WHERE w.tenant_id IN (v_tenant_a, v_tenant_b);
    ASSERT v_count = 1, format('1: list_tenko_overdue_webhook_configs が返した検査用の設定が %s 件 (1 件のはず)', v_count);

    -- create_access_request: テナント a の利用者が、テナント b への参加を申請する
    SELECT * INTO STRICT v_req FROM alc_api.create_access_request(v_tenant_b, v_user_g);
    ASSERT v_req.tenant_id = v_tenant_b AND v_req.user_id = v_user_g AND v_req.status = 'pending',
        '1: create_access_request が返した行が違う';

    -- leave_resolve_mailbox: 有効な宛先だけ引け、大文字でも引け、無効・未登録は 0 行
    SELECT * INTO STRICT v_leave
      FROM alc_api.leave_resolve_mailbox(upper('chk-' || substr(md5(v_key), 1, 12)));
    ASSERT v_leave.tenant_id = v_tenant_a AND v_leave.allowed_senders = ARRAY['sender@example.invalid'],
        '1: leave_resolve_mailbox が違う行を返した';
    SELECT count(*) INTO v_count
      FROM alc_api.leave_resolve_mailbox('chk-' || substr(md5(v_key || 'b'), 1, 12));
    ASSERT v_count = 0, '1: leave_resolve_mailbox が無効な宛先を返した';
    SELECT count(*) INTO v_count FROM alc_api.leave_resolve_mailbox(v_key || '-none');
    ASSERT v_count = 0, '1: leave_resolve_mailbox が、在るはずのない行を返した';

    -- leave_enabled_tenants (164): 有効な tenant だけが、tenant_id 順に返る
    SELECT array_agg(t.tenant_id ORDER BY t.tenant_id) INTO v_tenants
      FROM alc_api.leave_enabled_tenants() t WHERE t.tenant_id IN (v_tenant_a, v_tenant_b);
    ASSERT v_tenants = ARRAY[v_tenant_a], '1: leave_enabled_tenants が有効な tenant だけを返していない';

    RAISE NOTICE 'ok 1: 認証前・テナント横断の関数 11 本を、alc_api_rt が tenant context 無しで呼べる';
END
$$;

-- 1b. 適用履歴 (migration 160)。関数からは件数と最大 version の 1 行が返り、表の直読みは権限で落ちる。
DO $$
DECLARE
    v_count   BIGINT;
    v_applied BIGINT;
    v_max     BIGINT;
BEGIN
    SELECT count(*), min(s.applied), min(s.max_version)
      INTO v_count, v_applied, v_max
      FROM alc_api.migration_status() s;
    ASSERT v_count = 1, format('1b: migration_status が %s 行返した (1 行のはず)', v_count);
    ASSERT v_applied >= 1 AND v_max >= v_applied,
        format('1b: migration_status が applied = %s / max_version = %s を返した', v_applied, v_max);

    BEGIN
        PERFORM 1 FROM alc_api._sqlx_migrations LIMIT 1;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'ok 1b: alc_api_rt は適用履歴を関数からだけ読める (applied = % / max_version = %)', v_applied, v_max;
        RETURN;
    END;
    RAISE EXCEPTION '1b: alc_api_rt が _sqlx_migrations を直接読めてしまった';
END
$$;

-- 2. 同じ問い合わせを表へ直接打つと RLS が掛かる (関数が要る理由。所有者の接続だと素通りする)。
--    tenant context が無いので、users・devices・webhook_configs はポリシーの式がエラーになり、
--    tenant_allowed_emails は 0 行、access_requests の INSERT は拒否される。
DO $$
DECLARE
    v_sql   TEXT;
    v_count BIGINT;
BEGIN
    FOREACH v_sql IN ARRAY ARRAY[
        format('SELECT * FROM alc_api.users WHERE google_sub = %L', current_setting('chk.key') || '-g'),
        'SELECT id FROM alc_api.devices WHERE fcm_token IS NOT NULL',
        $q$SELECT * FROM alc_api.webhook_configs WHERE event_type = 'tenko_overdue'$q$,
        format('INSERT INTO alc_api.access_requests (tenant_id, user_id) VALUES (%L, %L)',
               current_setting('chk.tenant_b'), current_setting('chk.user_g'))
    ] LOOP
        BEGIN
            EXECUTE v_sql;
        EXCEPTION WHEN insufficient_privilege OR undefined_object OR invalid_text_representation THEN
            -- 42501 (RLS の拒否) / 42704 (app.current_* が未設定) / 22P02 (空文字の UUID)
            CONTINUE;
        END;
        RAISE EXCEPTION '2: tenant context 無しの alc_api_rt から、表への直接の問い合わせが通ってしまった: %', v_sql;
    END LOOP;

    SELECT count(*) INTO v_count FROM alc_api.tenant_allowed_emails;
    ASSERT v_count = 0, format('2: tenant context 無しの alc_api_rt から招待が %s 行見える (0 行のはず)', v_count);

    -- 163 の表のポリシーは NULLIF で未設定を NULL にするので、エラーではなく 0 行になる
    SELECT count(*) INTO v_count FROM alc_api.leave_settings;
    ASSERT v_count = 0, format('2: tenant context 無しの alc_api_rt から leave_settings が %s 行見える (0 行のはず)', v_count);

    RAISE NOTICE 'ok 2: 表への直接の問い合わせには RLS が掛かる (alc_api_rt は所有者でない)';
END
$$;

-- 3. tenant_allowed_emails のポリシーは alc_api_rt にも効く (migration 158 が宛先に足した)。
--    宛先に入っていないと、テナントを立てても 1 行も見えず、INSERT も拒否される。
DO $$
DECLARE
    v_count BIGINT;
BEGIN
    PERFORM alc_api.set_current_tenant(current_setting('chk.tenant_b'));
    SELECT count(*) INTO v_count FROM alc_api.tenant_allowed_emails;
    ASSERT v_count = 1, format('3: 自分のテナントの招待が %s 行見える (1 行のはず)', v_count);

    INSERT INTO alc_api.tenant_allowed_emails (tenant_id, email)
    VALUES (current_setting('chk.tenant_b')::UUID, current_setting('chk.key') || '-inv2@example.invalid');
    DELETE FROM alc_api.tenant_allowed_emails WHERE email = current_setting('chk.key') || '-inv2@example.invalid';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ASSERT v_count = 1, '3: 自分のテナントの招待を消せない';

    PERFORM alc_api.set_current_tenant(current_setting('chk.tenant_a'));
    SELECT count(*) INTO v_count FROM alc_api.tenant_allowed_emails;
    ASSERT v_count = 0, format('3: 別のテナントの招待が %s 行見える (0 行のはず)', v_count);

    RAISE NOTICE 'ok 3: tenant_allowed_emails は alc_api_rt から自分のテナントの行だけ読み書きできる';
END
$$;

RESET ROLE;

-- 4. 158 の 9 本・160 の 1 本・163 の 1 本・164 の 1 本は PUBLIC から REVOKE してある (権限を何も付けていないロールからは呼べない)。
--    _sqlx_migrations は alc_api_rt から読めない。
DO $$
DECLARE
    v_fn    TEXT;
    v_count INT := 0;
BEGIN
    FOREACH v_fn IN ARRAY ARRAY[
        'alc_api.find_user_by_google_sub(text)',
        'alc_api.find_user_by_lineworks_id(text)',
        'alc_api.save_user_refresh_token(uuid, text, timestamptz)',
        'alc_api.find_invitation_by_email(text)',
        'alc_api.list_fcm_devices()',
        'alc_api.list_all_callable_devices()',
        'alc_api.list_dev_device_tenant_ids()',
        'alc_api.list_tenko_overdue_webhook_configs()',
        'alc_api.create_access_request(uuid, uuid)',
        'alc_api.leave_resolve_mailbox(text)',
        'alc_api.leave_enabled_tenants()',
        'alc_api.migration_status()'
    ] LOOP
        ASSERT NOT has_function_privilege('chk_nobody', v_fn, 'EXECUTE'),
            format('4: %s が PUBLIC から呼べる', v_fn);
        ASSERT has_function_privilege('alc_api_app', v_fn, 'EXECUTE'),
            format('4: %s を alc_api_app が呼べない', v_fn);
        ASSERT has_function_privilege('alc_api_rt', v_fn, 'EXECUTE'),
            format('4: %s を alc_api_rt が呼べない', v_fn);
        ASSERT (SELECT p.prosecdef AND p.proconfig = ARRAY['search_path=alc_api']
                  FROM pg_proc p WHERE p.oid = v_fn::regprocedure),
            format('4: %s が SECURITY DEFINER + search_path = alc_api でない', v_fn);
        v_count := v_count + 1;
    END LOOP;

    ASSERT NOT has_table_privilege('alc_api_rt', 'alc_api._sqlx_migrations', 'SELECT'),
        '4: alc_api_rt が _sqlx_migrations を読める';

    -- migration_status が返す 2 値は、適用履歴の表を直接数えた値と同じ
    ASSERT (SELECT (s.applied, s.max_version) FROM alc_api.migration_status() s)
           = (SELECT (count(*), max(m.version)) FROM alc_api._sqlx_migrations m WHERE m.success),
        '4: migration_status の値が _sqlx_migrations と合わない';

    RAISE NOTICE 'ok 4: 関数 % 本は PUBLIC から呼べず、alc_api_app と alc_api_rt だけが呼べる', v_count;
END
$$;

ROLLBACK;
