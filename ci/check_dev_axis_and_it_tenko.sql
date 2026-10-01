-- CI の replay job 専用の検査 (migration 153〜156)。crate には含めない (scripts/ ではなく ci/ に置く)。
--
-- init → 全 migration → grants を流した後の DB に対して、アプリのロール alc_api_app で
-- 「dev の軸」(is_dev 列 + RLS + set_current_tenant) と 'IT点呼' を確かめる。
-- 全体を 1 transaction で流して最後に ROLLBACK するので、DB には何も残らない。
-- id はその場で作る (実在の tenant_id / device_id は書かない)。
--
--   psql -v ON_ERROR_STOP=1 -f ci/check_dev_axis_and_it_tenko.sql
--
-- どれか 1 つでも期待と違えば例外で止まる (psql の終了コードが 0 でなくなる)。

\set ON_ERROR_STOP on
SET plpgsql.check_asserts = on;

BEGIN;

-- ---------------------------------------------------------------------------
-- 準備 (superuser)。前提の行と、検査用の関数を作る
-- ---------------------------------------------------------------------------
SELECT set_config('chk.tenant_id', gen_random_uuid()::TEXT, false),
       set_config('chk.device_id', 'chk-' || gen_random_uuid()::TEXT, false) \gset chk_

INSERT INTO alc_api.tenants (id, name)
VALUES (current_setting('chk.tenant_id')::UUID, 'ci check');

WITH e AS (
    INSERT INTO alc_api.employees (tenant_id, name)
    VALUES (current_setting('chk.tenant_id')::UUID, 'ci check')
    RETURNING id
), w AS (
    INSERT INTO alc_api.webhook_configs (tenant_id, event_type, url)
    VALUES (current_setting('chk.tenant_id')::UUID, 'equipment_failure', 'https://example.invalid/')
    RETURNING id
), c AS (
    INSERT INTO alc_api.carrying_items (tenant_id, item_name)
    VALUES (current_setting('chk.tenant_id')::UUID, 'ci check')
    RETURNING id
)
SELECT set_config('chk.employee_id', e.id::TEXT, false),
       set_config('chk.webhook_config_id', w.id::TEXT, false),
       set_config('chk.carrying_item_id', c.id::TEXT, false)
  FROM e, w, c \gset chk_

CREATE SCHEMA chk;
GRANT USAGE ON SCHEMA chk TO alc_api_app;

-- 8 表の「いまの接続から見える行数」。SECURITY INVOKER なので呼んだロールの RLS が効く。
-- 順番: tenko_schedules, measurements, tenko_sessions, tenko_records,
--       tenko_carrying_item_checks, hub_measurements, webhook_deliveries, equipment_failures
CREATE FUNCTION chk.visible() RETURNS INT[]
LANGUAGE sql AS $$
    SELECT ARRAY[
        (SELECT count(*) FROM alc_api.tenko_schedules),
        (SELECT count(*) FROM alc_api.measurements),
        (SELECT count(*) FROM alc_api.tenko_sessions),
        (SELECT count(*) FROM alc_api.tenko_records),
        (SELECT count(*) FROM alc_api.tenko_carrying_item_checks),
        (SELECT count(*) FROM alc_api.hub_measurements),
        (SELECT count(*) FROM alc_api.webhook_deliveries),
        (SELECT count(*) FROM alc_api.equipment_failures)
    ]::INT[];
$$;

-- 8 表に 1 行ずつ、is_dev を指定せずに INSERT する (backend と同じ書き方)。
-- 入った行の is_dev を chk.visible() と同じ順で返す。p_seq は hub_measurements の seq。
CREATE FUNCTION chk.insert_all(p_seq BIGINT) RETURNS BOOLEAN[]
LANGUAGE plpgsql AS $$
DECLARE
    v_tenant   CONSTANT UUID := current_setting('chk.tenant_id')::UUID;
    v_employee CONSTANT UUID := current_setting('chk.employee_id')::UUID;
    v_session  UUID;
    v          BOOLEAN;
    v_out      BOOLEAN[] := '{}';
BEGIN
    INSERT INTO alc_api.tenko_schedules (tenant_id, employee_id, tenko_type, responsible_manager_name, scheduled_at)
    VALUES (v_tenant, v_employee, 'post_operation', 'ci check', now())
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    INSERT INTO alc_api.measurements (tenant_id, employee_id)
    VALUES (v_tenant, v_employee)
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    INSERT INTO alc_api.tenko_sessions (tenant_id, employee_id, tenko_type)
    VALUES (v_tenant, v_employee, 'post_operation')
    RETURNING id, is_dev INTO v_session, v;
    v_out := v_out || v;
    -- 作った session の id を chk.session_<seq> に控える (軸をまたぐ参照の検査で使う)
    PERFORM set_config('chk.session_' || p_seq, v_session::TEXT, false);

    INSERT INTO alc_api.tenko_records
        (tenant_id, session_id, employee_id, tenko_type, status, record_data, employee_name, record_hash)
    VALUES (v_tenant, v_session, v_employee, 'post_operation', 'completed', '{}', 'ci check', 'ci check')
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    INSERT INTO alc_api.tenko_carrying_item_checks (session_id, item_id, item_name)
    VALUES (v_session, current_setting('chk.carrying_item_id')::UUID, 'ci check')
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    INSERT INTO alc_api.hub_measurements (tenant_id, device_id, kind, payload, seq)
    VALUES (v_tenant, current_setting('chk.device_id'), 'temperature', '{}', p_seq)
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    INSERT INTO alc_api.webhook_deliveries (tenant_id, config_id, event_type, payload)
    VALUES (v_tenant, current_setting('chk.webhook_config_id')::UUID, 'equipment_failure', '{}')
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    INSERT INTO alc_api.equipment_failures (tenant_id, failure_type, description)
    VALUES (v_tenant, 'manual_report', 'ci check')
    RETURNING is_dev INTO v;
    v_out := v_out || v;

    RETURN v_out;
END
$$;

-- 8 表それぞれに is_dev を明示して INSERT し、全部が RLS (42501) で拒否されることを確かめる。
-- 1 表でも通ったら例外。
CREATE FUNCTION chk.expect_explicit_insert_rejected(p_is_dev BOOLEAN) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_tenant   CONSTANT UUID := current_setting('chk.tenant_id')::UUID;
    v_employee CONSTANT UUID := current_setting('chk.employee_id')::UUID;
    v_session  UUID;
    v_sql      TEXT;
BEGIN
    -- 親になる session は、いまの接続の軸で見えるものを使う
    SELECT id INTO STRICT v_session FROM alc_api.tenko_sessions ORDER BY created_at LIMIT 1;

    FOREACH v_sql IN ARRAY ARRAY[
        format($q$INSERT INTO alc_api.tenko_schedules (tenant_id, employee_id, tenko_type, responsible_manager_name, scheduled_at, is_dev)
                  VALUES (%L, %L, 'post_operation', 'ci check', now(), %L)$q$, v_tenant, v_employee, p_is_dev),
        format($q$INSERT INTO alc_api.measurements (tenant_id, employee_id, is_dev)
                  VALUES (%L, %L, %L)$q$, v_tenant, v_employee, p_is_dev),
        format($q$INSERT INTO alc_api.tenko_sessions (tenant_id, employee_id, tenko_type, is_dev)
                  VALUES (%L, %L, 'post_operation', %L)$q$, v_tenant, v_employee, p_is_dev),
        format($q$INSERT INTO alc_api.tenko_records
                      (tenant_id, session_id, employee_id, tenko_type, status, record_data, employee_name, record_hash, is_dev)
                  VALUES (%L, %L, %L, 'post_operation', 'completed', '{}', 'ci check', 'ci check', %L)$q$,
               v_tenant, v_session, v_employee, p_is_dev),
        format($q$INSERT INTO alc_api.tenko_carrying_item_checks (session_id, item_id, item_name, is_dev)
                  VALUES (%L, %L, 'ci check', %L)$q$,
               v_session, current_setting('chk.carrying_item_id'), p_is_dev),
        format($q$INSERT INTO alc_api.hub_measurements (tenant_id, device_id, kind, payload, seq, is_dev)
                  VALUES (%L, %L, 'temperature', '{}', 9000, %L)$q$,
               v_tenant, current_setting('chk.device_id'), p_is_dev),
        format($q$INSERT INTO alc_api.webhook_deliveries (tenant_id, config_id, event_type, payload, is_dev)
                  VALUES (%L, %L, 'equipment_failure', '{}', %L)$q$,
               v_tenant, current_setting('chk.webhook_config_id'), p_is_dev),
        format($q$INSERT INTO alc_api.equipment_failures (tenant_id, failure_type, description, is_dev)
                  VALUES (%L, 'manual_report', 'ci check', %L)$q$, v_tenant, p_is_dev)
    ] LOOP
        BEGIN
            EXECUTE v_sql;
        EXCEPTION WHEN insufficient_privilege THEN
            CONTINUE;
        END;
        RAISE EXCEPTION 'is_dev = % を明示した INSERT が RLS で拒否されなかった: %', p_is_dev, v_sql;
    END LOOP;
END
$$;

-- 8 表それぞれで、いま見えている行の is_dev を p_to へ書き換える UPDATE が、全部 RLS (42501) で
-- 拒否されることを確かめる。1 表でも通ったら (0 行で空振りした場合も) 例外。
CREATE FUNCTION chk.expect_axis_update_rejected(p_to BOOLEAN) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_tbl TEXT;
BEGIN
    FOREACH v_tbl IN ARRAY ARRAY[
        'tenko_schedules', 'measurements', 'tenko_sessions', 'tenko_records',
        'tenko_carrying_item_checks', 'hub_measurements', 'webhook_deliveries', 'equipment_failures'
    ] LOOP
        BEGIN
            IF v_tbl = 'tenko_records' THEN
                -- 完了済みの行の UPDATE は trigger が RLS より先に止める (検査 7)。
                -- 完了していない行を作って確かめる (拒否の例外で、この行ごと巻き戻る)。
                INSERT INTO alc_api.tenko_records
                    (tenant_id, session_id, employee_id, tenko_type, status, record_data, employee_name, record_hash)
                SELECT s.tenant_id, s.id, s.employee_id, 'post_operation', 'cancelled', '{}', 'ci check', 'ci check'
                  FROM alc_api.tenko_sessions s
                 ORDER BY s.created_at
                 LIMIT 1;
                UPDATE alc_api.tenko_records SET is_dev = p_to WHERE status <> 'completed';
            ELSE
                EXECUTE format('UPDATE alc_api.%I SET is_dev = %L', v_tbl, p_to);
            END IF;
        EXCEPTION WHEN insufficient_privilege THEN
            CONTINUE;
        END;
        RAISE EXCEPTION 'alc_api.% の is_dev を % へ書き換える UPDATE が RLS で拒否されなかった', v_tbl, p_to;
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- ここからアプリのロール (NOBYPASSRLS)
-- ---------------------------------------------------------------------------
SET ROLE alc_api_app;

-- 0. app.device_dev を一度も立てていない接続 (migration 適用直後の古い backend と同じ)。
--    set_current_tenant も通さず、テナントだけを直接立てる。未設定 (NULL) は dev でない。
DO $$
BEGIN
    ASSERT current_setting('app.device_dev', true) IS NULL,
        '0: 新しい接続なのに app.device_dev が設定済み';
    PERFORM set_config('app.current_tenant_id', current_setting('chk.tenant_id'), false);

    ASSERT chk.insert_all(1) = ARRAY[false, false, false, false, false, false, false, false],
        '0: 未設定の接続で書いた行が is_dev = false になっていない';
    ASSERT chk.visible() = ARRAY[1, 1, 1, 1, 1, 1, 1, 1],
        format('0: 未設定の接続から自分の行が見えない: %s', chk.visible());
    RAISE NOTICE 'ok 0: app.device_dev が未設定の接続は dev でない (8 表)';
END
$$;

-- 1. set_current_tenant だけ呼んだ接続 → is_dev = false で入り、同じ接続から見える。
DO $$
BEGIN
    PERFORM alc_api.set_current_tenant(current_setting('chk.tenant_id'));
    ASSERT current_setting('app.device_dev', true) = '',
        format('1: set_current_tenant の後の app.device_dev が空文字でない: %L', current_setting('app.device_dev', true));

    ASSERT chk.insert_all(2) = ARRAY[false, false, false, false, false, false, false, false],
        '1: dev でない接続で書いた行が is_dev = false になっていない';
    ASSERT chk.visible() = ARRAY[2, 2, 2, 2, 2, 2, 2, 2],
        format('1: dev でない接続から見える行数が違う: %s', chk.visible());
    RAISE NOTICE 'ok 1: set_current_tenant だけの接続は is_dev = false で書き、その行が見える (8 表)';
END
$$;

-- 2. 続けて app.device_dev = '1' → is_dev = true で入り、見えるのは dev の行だけ。
DO $$
BEGIN
    PERFORM set_config('app.device_dev', '1', false);

    ASSERT chk.visible() = ARRAY[0, 0, 0, 0, 0, 0, 0, 0],
        format('2: dev の接続から本番の行が見えている: %s', chk.visible());
    ASSERT chk.insert_all(3) = ARRAY[true, true, true, true, true, true, true, true],
        '2: dev の接続で書いた行が is_dev = true になっていない';
    ASSERT chk.visible() = ARRAY[1, 1, 1, 1, 1, 1, 1, 1],
        format('2: dev の接続から見える行数が違う: %s', chk.visible());
    RAISE NOTICE 'ok 2: dev の接続は is_dev = true で書き、dev の行だけが見える (8 表)';
END
$$;

-- 2b. dev の接続から、本番の session (検査 1 で作った、dev からは見えない) を指す行。
--     chk.session_2 = 本番の session、chk.session_3 = dev の session。
DO $$
DECLARE
    v_is_dev BOOLEAN;
    v_count  BIGINT;
BEGIN
    -- tenko_carrying_item_checks: ポリシーが session を tenko_sessions の RLS 越しに引くので、
    -- 見えない session を指す行は拒否される。
    BEGIN
        INSERT INTO alc_api.tenko_carrying_item_checks (session_id, item_id, item_name)
        VALUES (current_setting('chk.session_2')::UUID, current_setting('chk.carrying_item_id')::UUID, 'ci check');
        RAISE EXCEPTION '2b: dev の接続から本番の session を指す携行品チェックを INSERT できてしまった';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;

    -- tenko_records: ポリシーは session を見ず、FK の参照整合は RLS を迂回するので、
    -- 見えない本番の session の id を指す INSERT は「通る」(今回の設計の既知の性質)。
    -- 入った行は dev の行 (is_dev = true) で、本番の接続からは見えない (検査 3b)。
    INSERT INTO alc_api.tenko_records
        (tenant_id, session_id, employee_id, tenko_type, status, record_data, employee_name, record_hash)
    VALUES (current_setting('chk.tenant_id')::UUID, current_setting('chk.session_2')::UUID,
            current_setting('chk.employee_id')::UUID, 'post_operation', 'completed', '{}', 'ci check', 'ci check')
    RETURNING is_dev INTO v_is_dev;
    ASSERT v_is_dev, '2b: dev の接続から本番の session を指して書いた tenko_records が is_dev = true になっていない';

    SELECT count(*) INTO v_count FROM alc_api.tenko_records
     WHERE session_id = current_setting('chk.session_2')::UUID;
    ASSERT v_count = 1, format('2b: dev の接続から、本番の session を指す tenko_records が %s 行見える (自分の 1 行だけのはず)', v_count);

    RAISE NOTICE 'ok 2b: dev の接続から本番の session を指す行 — 携行品チェックは拒否、tenko_records は dev の行として入る';
END
$$;

-- 4a. dev の接続から is_dev = false を明示した INSERT / UPDATE は拒否される (8 表)。
DO $$
BEGIN
    PERFORM chk.expect_explicit_insert_rejected(false);
    PERFORM chk.expect_axis_update_rejected(false);
    RAISE NOTICE 'ok 4a: dev の接続からの is_dev = false の明示は RLS で拒否 (INSERT 8 表 + UPDATE 8 表)';
END
$$;

-- 3. もう一度 set_current_tenant → 設定値が消え、見えるのは dev でない行だけ。
DO $$
BEGIN
    PERFORM alc_api.set_current_tenant(current_setting('chk.tenant_id'));
    ASSERT current_setting('app.device_dev', true) = '',
        format('3: set_current_tenant が app.device_dev を消していない: %L', current_setting('app.device_dev', true));
    ASSERT chk.visible() = ARRAY[2, 2, 2, 2, 2, 2, 2, 2],
        format('3: dev でない接続へ戻した後に見える行数が違う: %s', chk.visible());
    RAISE NOTICE 'ok 3: set_current_tenant は app.device_dev を消し、dev の行は見えなくなる (8 表)';
END
$$;

-- 3b. dev でない接続から、dev の session を指す行 (2b の逆向き)。
DO $$
DECLARE
    v_count BIGINT;
BEGIN
    BEGIN
        INSERT INTO alc_api.tenko_carrying_item_checks (session_id, item_id, item_name)
        VALUES (current_setting('chk.session_3')::UUID, current_setting('chk.carrying_item_id')::UUID, 'ci check');
        RAISE EXCEPTION '3b: dev でない接続から dev の session を指す携行品チェックを INSERT できてしまった';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;

    -- 2b で dev の接続が本番の session を指して書いた tenko_records は、本番からは見えない。
    -- 見えるのは検査 1 で作った本番の 1 行だけ。
    SELECT count(*) INTO v_count FROM alc_api.tenko_records
     WHERE session_id = current_setting('chk.session_2')::UUID;
    ASSERT v_count = 1, format('3b: 本番の session を指す tenko_records が本番の接続から %s 行見える (1 行のはず)', v_count);

    RAISE NOTICE 'ok 3b: dev でない接続から dev の session を指す携行品チェックは拒否。dev が書いた tenko_records は見えない';
END
$$;

-- 4b. dev でない接続から is_dev = true を明示した INSERT / UPDATE は拒否される (8 表)。
DO $$
BEGIN
    PERFORM chk.expect_explicit_insert_rejected(true);
    PERFORM chk.expect_axis_update_rejected(true);
    RAISE NOTICE 'ok 4b: dev でない接続からの is_dev = true の明示は RLS で拒否 (INSERT 8 表 + UPDATE 8 表)';
END
$$;

-- 5. hub_measurements: 3 列の unique は無く (migration 156)、4 列の unique index だけが在る。
--    同じ (tenant, device, seq) が dev の軸と本番の軸の両方に入り、
--    同じ軸での再送は ON CONFLICT (tenant_id, device_id, seq, is_dev) で弾かれる。
--    ここまでの行: 本番の軸に seq 1・2 (検査 0・1)、dev の軸に seq 3 (検査 2)。
DO $$
DECLARE
    v_tenant CONSTANT UUID := current_setting('chk.tenant_id')::UUID;
    v_device CONSTANT TEXT := current_setting('chk.device_id');
    v_count  BIGINT;
    v_rows   BIGINT;
BEGIN
    -- (a) 鍵の列がちょうど tenant_id / device_id / seq の 3 つである unique は、制約としても
    --     index としても残っていない。
    SELECT count(*) INTO v_count
      FROM pg_constraint c
     WHERE c.conrelid = 'alc_api.hub_measurements'::regclass
       AND c.contype = 'u'
       AND cardinality(c.conkey) = 3
       AND (
           SELECT array_agg(a.attname::TEXT)
             FROM pg_attribute a
            WHERE a.attrelid = c.conrelid
              AND a.attnum = ANY (c.conkey)
       ) @> ARRAY['tenant_id', 'device_id', 'seq'];
    ASSERT v_count = 0, format('5a: hub_measurements に 3 列の UNIQUE 制約が %s 個残っている', v_count);
    ASSERT NOT EXISTS (
        SELECT 1 FROM pg_indexes
         WHERE schemaname = 'alc_api'
           AND tablename = 'hub_measurements'
           AND indexdef LIKE 'CREATE UNIQUE INDEX %(tenant_id, device_id, seq)'
    ), '5a: hub_measurements に 3 列の unique index が残っている';

    -- (b) 4 列の unique index は在る。
    ASSERT EXISTS (
        SELECT 1 FROM pg_indexes
         WHERE schemaname = 'alc_api'
           AND tablename = 'hub_measurements'
           AND indexname = 'hub_measurements_tenant_device_seq_is_dev'
           AND indexdef LIKE 'CREATE UNIQUE INDEX %(tenant_id, device_id, seq, is_dev)'
    ), '5b: hub_measurements の 4 列 unique index が無い';

    -- (d) 本番の軸: seq 2 は本番に既に在るので、再送は 0 行。
    INSERT INTO alc_api.hub_measurements (tenant_id, device_id, kind, payload, seq)
    VALUES (v_tenant, v_device, 'temperature', '{}', 2)
    ON CONFLICT (tenant_id, device_id, seq, is_dev) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    ASSERT v_rows = 0, '5d: 本番の軸で同じ seq の再送が 4 列の ON CONFLICT で弾かれなかった';

    -- (c) 本番の軸: seq 3 は dev の軸にだけ在る。本番にも入る。
    INSERT INTO alc_api.hub_measurements (tenant_id, device_id, kind, payload, seq)
    VALUES (v_tenant, v_device, 'temperature', '{}', 3)
    ON CONFLICT (tenant_id, device_id, seq, is_dev) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    ASSERT v_rows = 1, '5c: dev の軸に在る seq が本番の軸に入らなかった';

    PERFORM set_config('app.device_dev', '1', false);

    -- (d) dev の軸: seq 3 は dev に既に在るので、再送は 0 行。
    INSERT INTO alc_api.hub_measurements (tenant_id, device_id, kind, payload, seq)
    VALUES (v_tenant, v_device, 'temperature', '{}', 3)
    ON CONFLICT (tenant_id, device_id, seq, is_dev) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    ASSERT v_rows = 0, '5d: dev の軸で同じ seq の再送が 4 列の ON CONFLICT で弾かれなかった';

    -- (c) dev の軸: seq 2 は本番の軸にだけ在る。dev にも入る。
    INSERT INTO alc_api.hub_measurements (tenant_id, device_id, kind, payload, seq)
    VALUES (v_tenant, v_device, 'temperature', '{}', 2)
    ON CONFLICT (tenant_id, device_id, seq, is_dev) DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    ASSERT v_rows = 1, '5c: 本番の軸に在る seq が dev の軸に入らなかった';

    -- 見える行数で両方の軸を確かめる: dev は seq 2・3、本番は seq 1・2・3。
    SELECT count(*) INTO v_count FROM alc_api.hub_measurements;
    ASSERT v_count = 2, format('5c: dev の接続から見える hub_measurements が %s 行 (2 行のはず)', v_count);
    PERFORM alc_api.set_current_tenant(current_setting('chk.tenant_id'));
    SELECT count(*) INTO v_count FROM alc_api.hub_measurements;
    ASSERT v_count = 3, format('5c: 本番の接続から見える hub_measurements が %s 行 (3 行のはず)', v_count);

    RAISE NOTICE 'ok 5: hub_measurements の 3 列 unique は無く、同じ seq が dev と本番の両方に入る。同じ軸の再送は 4 列の ON CONFLICT で弾く';
END
$$;

-- 6. 'IT点呼' が通り、存在しない方法名は CHECK で落ちる。
--    IT点呼 の冪等 (tenko_type が pre_operation でも部分 unique に掛かる) と、
--    その鍵に is_dev が入っていること (dev と本番は互いを理由に捨てられない)。
DO $$
DECLARE
    v_tenant   CONSTANT UUID := current_setting('chk.tenant_id')::UUID;
    v_employee CONSTANT UUID := current_setting('chk.employee_id')::UUID;
    v_started  CONSTANT TIMESTAMPTZ := now();
    v_rows     BIGINT;
BEGIN
    INSERT INTO alc_api.tenko_sessions (tenant_id, employee_id, tenko_type, tenko_method, started_at)
    VALUES (v_tenant, v_employee, 'pre_operation', 'IT点呼', v_started);

    BEGIN
        INSERT INTO alc_api.tenko_sessions (tenant_id, employee_id, tenko_type, tenko_method)
        VALUES (v_tenant, v_employee, 'pre_operation', '存在しない点呼');
        RAISE EXCEPTION '6: 存在しない点呼方法が CHECK を通ってしまった';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO alc_api.tenko_sessions (tenant_id, employee_id, tenko_type, tenko_method, started_at)
    VALUES (v_tenant, v_employee, 'pre_operation', 'IT点呼', v_started)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    ASSERT v_rows = 0, '6: 同じ乗務員・同じ開始時刻の IT点呼 が 2 行入った';

    PERFORM set_config('app.device_dev', '1', false);
    INSERT INTO alc_api.tenko_sessions (tenant_id, employee_id, tenko_type, tenko_method, started_at)
    VALUES (v_tenant, v_employee, 'pre_operation', 'IT点呼', v_started)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    ASSERT v_rows = 1, '6: dev の IT点呼 が本番の行を理由に捨てられた';

    PERFORM alc_api.set_current_tenant(current_setting('chk.tenant_id'));
    RAISE NOTICE 'ok 6: IT点呼 は通り、未知の方法名は CHECK で落ちる。冪等の鍵は is_dev を含む';
END
$$;

-- 7. tenko_records の trigger は列の追加で壊れていない (完了済みの行の UPDATE は従来どおり例外)。
DO $$
BEGIN
    BEGIN
        UPDATE alc_api.tenko_records SET location = 'ci check' WHERE status = 'completed';
        RAISE EXCEPTION '7: 完了済みの tenko_records を UPDATE できてしまった';
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM = 'Cannot modify completed tenko record',
            format('7: 想定と違う例外: %s', SQLERRM);
    END;
    RAISE NOTICE 'ok 7: 完了済みの tenko_records の UPDATE は trigger が止める';
END
$$;

-- 8. 別のテナントからは dev でも本番でも見えない (テナントの条件が残っていること)。
DO $$
BEGIN
    PERFORM alc_api.set_current_tenant(gen_random_uuid()::TEXT);
    ASSERT chk.visible() = ARRAY[0, 0, 0, 0, 0, 0, 0, 0],
        format('8: 別テナントの本番の接続から行が見えている: %s', chk.visible());
    PERFORM set_config('app.device_dev', '1', false);
    ASSERT chk.visible() = ARRAY[0, 0, 0, 0, 0, 0, 0, 0],
        format('8: 別テナントの dev の接続から行が見えている: %s', chk.visible());
    RAISE NOTICE 'ok 8: 別のテナントからは dev でも本番でも見えない (8 表)';
END
$$;

RESET ROLE;
ROLLBACK;
