-- CI の replay job 専用の検査。crate には含めない (scripts/ ではなく ci/ に置く)。
--
-- テナント分離のポリシーが、実行用ロール alc_api_rt に対して「実際の行」を止めることを、
-- alc_api schema の tenant_id 列を持つ表の全部で確かめる。表は列挙せず、カタログから引く
-- (表を足しても、この検査に手を入れなくてよい)。
-- ci/check_rls_invariants.sql はカタログを読むだけなので、式が true ではないが間違っている
-- ポリシー (別の GUC 名・余計な OR・IS NOT NULL など) を落とせない。それをここで落とす。
--
-- 違反を 1 行ずつ返す (check, object, detail)。0 行なら合格。数の内訳は NOTICE (stderr) に出す。
-- このファイルは BEGIN / ROLLBACK を持たない。呼ぶ側が 1 transaction で包み、最後に ROLLBACK する
-- (DB には何も残らない。tenko_records は UPDATE / DELETE を trigger が止めるので、後始末は ROLLBACK だけ)。
-- ON_ERROR_STOP を外さない — 無いと SQL のエラーでも出力が空になり、合格に見える。
--
--   psql -v ON_ERROR_STOP=1 -q -At -F ' | ' -c BEGIN -f ci/check_rls_rows.sql -c ROLLBACK
--
-- 接続は superuser (行を入れるのは superuser。FORCE の表にも入る)。検査 a・b・c は、どちらの軸でも
-- SET LOCAL ROLE alc_api_rt で流す (所有者で流すと、FORCE の無い表は素通りする)。
-- id はその場で作る (実在の tenant_id は書かない)。
--
-- 検査 (テナントを 2 つ (A・B) 作り、各表に A の行と B の行を 1 つずつ入れてから):
--   a.     テナントを設定しない transaction では、1 行も読めない
--          (42704 = app.current_tenant_id が未設定 / 22P02 = 空文字の UUID / 0 行、のどれか)。
--          1 つの表のポリシーの式は OR で評価され、順は決まっていない。未設定でエラーになる式が
--          先に評価されると、緩い式が在っても a はエラー (合格) になる — その場合も b が落とす
--   b.     テナント A を設定すると、A の行は見え、A 以外の行は見えない
--          (自分の行も見えない「空振り」は合格に数えない)
--   c.     テナント A を設定して、tenant_id だけを B にした行を INSERT すると 42501 (RLS の拒否)。
--          成功も、42501 以外のエラーも違反 (別のエラーを合格に数えない)
--   seed.  tenant_id を持つ表の全部に、A・B の行を入れられる (入れられない表を黙って飛ばさない)。
--          入れた後に、A の行と B の行が実際に在ることを superuser で数える
--          (B の行が無いと、b の「A 以外の行が見えない」が空振りで合格になる)
--   exception. 下の「例外」に載せた表が、いまも例外のとおりに振る舞う (古くなった例外を残さない)
--   count. a・b を確かめた表の数 = tenant_id を持つ表の数 − a・b の例外、
--          c を確かめた表の数 = tenant_id を持つ表の数 − c の例外 (数はカタログから数える)
--
-- 行の入れ方 (NOT NULL で既定値の無い列だけを埋める。規則は表に依らない):
--   * tenant_id          — そのテナント
--   * 外部キーの列       — 親の表の、同じテナントの行 (親 → 子の順は、入る表が増えなくなるまで繰り返す)
--   * CHECK が「列 = ANY (ARRAY[値, …])」(列 IN (…)) の列 — 許される値の 1 つめ
--   * それ以外           — 型から作る (text は乱数、uuid は生成、数値は 1、…)
-- 複数の列にまたがる CHECK は上の規則で満たせないので、その表だけ「種」(列と値の指定) を持つ。
-- いま 3 表。表を足して seed の違反が出たら、まず規則で入らないかを考え、だめなら種を足す:
--   * users             — user_has_provider (google_sub / lineworks_id / line_user_id のどれかが要る)
--   * tenko_schedules   — chk_pre_operation_instruction (規則が選ぶ pre_operation は instruction が要る)
--   * notify_recipients — at_least_one_messaging_id (lineworks_user_id / line_user_id のどれかが要る)
--
-- 例外 (いま在るものを固定しているだけ。足さない):
--   RLS が無効 (a・b は「全部のテナントの行が見える」、c は「通る」が期待)。
--   理由は check_rls_invariants.sql の検査 3 の許可リストと同じ:
--   * vehicle_settings_dumps
--   読み (a・b は「全部のテナントの行が見える」が期待)。SELECT のポリシーが USING (true)。
--   理由は check_rls_invariants.sql の検査 8 の許可リストと同じ:
--   * tenko_call_numbers / tenko_call_drivers (tenant_id は TEXT)
--   * device_registration_requests
--   書き (c は「通る」が期待)。check_rls_invariants.sql の許可リストに対応するものは無い
--   (検査 8 が見るのは式が true そのもののポリシーだけ)。式は true ではないが、tenant_id を見ない:
--   * device_registration_requests  — device_reg_insert (migration 062):
--                                       FOR INSERT WITH CHECK (status = 'pending')
--                                     status が pending なら、どのテナントの tenant_id でも通る
--                                     (テナントに属する前の端末が、登録の申請を出す)
--   * access_requests               — access_requests_insert (migration 083):
--                                       FOR INSERT WITH CHECK (user_id = current_setting('app.current_user_id')::UUID)
--                                     user_id が自分なら、どのテナント宛てでも通る
--                                     (テナントに属する前の利用者が、参加の申請を出す)。
--                                     c は app.current_user_id に A の利用者を立てて流す
--
-- 対象外 (tenant_id 列を持たない表。黙って外しているのではない):
--   * carrying_item_vehicle_conditions / guidance_record_attachments / notify_recipient_groups /
--     tenko_call_logs / tenko_carrying_item_checks — ポリシーが親の表を subquery で引く。
--     テナントの列が無いので、この検査の「tenant_id だけを替える」形に載らない
--   * tenants / _sqlx_migrations — テナントの一覧と適用履歴 (検査 3 の許可リスト)
--
-- この検査が見ないもの: app.current_tenant_id のほかの GUC (app.current_organization_id・
-- alc_api.archive_mode など) を立てたときの振る舞い。UPDATE / DELETE。

-- 結果の置き場。ON COMMIT DROP なので、transaction の外で流すと次の文が「表が無い」で止まる
-- (BEGIN で包まずに流して、行を DB に残してしまうのを防ぐ)。
CREATE TEMP TABLE chk_rls_rows (
    tbl        TEXT PRIMARY KEY,
    tbl_oid    OID NOT NULL,
    read_open  BOOLEAN NOT NULL DEFAULT false,  -- 読みの例外 (全部のテナントの行が見えるのが期待)
    write_open BOOLEAN NOT NULL DEFAULT false,  -- 書きの例外 (別のテナントの tenant_id で書けるのが期待)
    seeded     BOOLEAN NOT NULL DEFAULT false,  -- A・B の行を入れられた
    why        TEXT,                            -- 入れられなかった理由
    insert_b   TEXT,                            -- c で流す文 (A の行の tenant_id だけを B にしたもの)
    a_done     BOOLEAN NOT NULL DEFAULT false,
    b_done     BOOLEAN NOT NULL DEFAULT false,
    c_done     BOOLEAN NOT NULL DEFAULT false
) ON COMMIT DROP;

CREATE TEMP TABLE chk_rls_violations (
    chk    TEXT NOT NULL,
    object TEXT NOT NULL,
    detail TEXT NOT NULL
) ON COMMIT DROP;

-- 例外 (理由は冒頭)。guc / guc_col は、c の前に立てる GUC と、その値を取る列 (INSERT する行の列)。
CREATE TEMP TABLE chk_rls_exceptions (
    tbl        TEXT PRIMARY KEY,
    read_open  BOOLEAN NOT NULL,
    write_open BOOLEAN NOT NULL,
    guc        TEXT,
    guc_col    TEXT
) ON COMMIT DROP;

INSERT INTO chk_rls_exceptions (tbl, read_open, write_open, guc, guc_col) VALUES
    ('vehicle_settings_dumps',       true,  true,  NULL, NULL),
    ('tenko_call_numbers',           true,  false, NULL, NULL),
    ('tenko_call_drivers',           true,  false, NULL, NULL),
    ('device_registration_requests', true,  true,  NULL, NULL),
    ('access_requests',              false, true,  'app.current_user_id', 'user_id');

-- 種 (理由は冒頭)。expr は INSERT の VALUES にそのまま入る式。
CREATE TEMP TABLE chk_rls_seeds (
    tbl  TEXT NOT NULL,
    col  TEXT NOT NULL,
    expr TEXT NOT NULL,
    PRIMARY KEY (tbl, col)
) ON COMMIT DROP;

INSERT INTO chk_rls_seeds (tbl, col, expr) VALUES
    ('users',             'google_sub',   'md5(gen_random_uuid()::text)'),
    ('tenko_schedules',   'tenko_type',   '''post_operation'''),
    ('notify_recipients', 'provider',     '''line'''),
    ('notify_recipients', 'line_user_id', 'md5(gen_random_uuid()::text)');

-- 1 行ぶんの INSERT 文を組む。p_tenant = tenant_id に入れる値、p_parent_tenant = 親の行を探すテナント
-- (種の行は両方同じ。c の行は tenant_id だけが別)。組めなければ例外 (呼ぶ側が理由として控える)。
CREATE FUNCTION pg_temp.chk_rls_insert_sql(p_table OID, p_tenant TEXT, p_parent_tenant TEXT) RETURNS TEXT
LANGUAGE plpgsql AS $fn$
DECLARE
    c      RECORD;
    v      TEXT;
    v_cols TEXT[] := '{}';
    v_vals TEXT[] := '{}';
BEGIN
    FOR c IN
        SELECT a.attname::TEXT AS col,
               format_type(a.atttypid, NULL) AS typ,
               a.attnotnull AND NOT a.atthasdef AND a.attidentity = '' AS required,
               s.expr AS seed_expr,
               fk.parent, fk.parent_col, fk.parent_filter,
               ck.val AS check_val
          FROM pg_attribute a
          JOIN pg_class t ON t.oid = a.attrelid
          LEFT JOIN chk_rls_seeds s ON s.tbl = t.relname AND s.col = a.attname
          LEFT JOIN LATERAL (
              SELECT k.confrelid::regclass AS parent,
                     pa.attname::TEXT AS parent_col,
                     CASE WHEN k.confrelid = 'alc_api.tenants'::regclass THEN 'id'
                          WHEN EXISTS (SELECT 1 FROM pg_attribute ta
                                        WHERE ta.attrelid = k.confrelid AND ta.attname = 'tenant_id'
                                          AND NOT ta.attisdropped) THEN 'tenant_id'
                     END AS parent_filter
                FROM pg_constraint k
                JOIN pg_attribute pa ON pa.attrelid = k.confrelid AND pa.attnum = k.confkey[1]
               WHERE k.contype = 'f' AND k.conrelid = a.attrelid AND k.conkey = ARRAY[a.attnum]
               ORDER BY k.oid
               LIMIT 1
          ) fk ON true
          LEFT JOIN LATERAL (
              SELECT (regexp_match(pg_get_constraintdef(k.oid), $re$ = ANY \(ARRAY\['([^']*)'$re$))[1] AS val
                FROM pg_constraint k
               WHERE k.contype = 'c' AND k.conrelid = a.attrelid AND k.conkey = ARRAY[a.attnum]
                 AND pg_get_constraintdef(k.oid) ~ $re$ = ANY \(ARRAY\['$re$
               ORDER BY k.oid
               LIMIT 1
          ) ck ON true
         WHERE a.attrelid = p_table AND a.attnum > 0 AND NOT a.attisdropped
         ORDER BY a.attnum
    LOOP
        IF c.col = 'tenant_id' THEN
            v := format('%L::%s', p_tenant, c.typ);
        ELSIF c.seed_expr IS NOT NULL THEN
            v := c.seed_expr;
        ELSIF NOT c.required THEN
            CONTINUE;
        ELSIF c.parent IS NOT NULL THEN
            EXECUTE format('SELECT (SELECT %I::TEXT FROM %s %s ORDER BY 1 LIMIT 1)', c.parent_col, c.parent,
                           CASE WHEN c.parent_filter IS NOT NULL
                                THEN format('WHERE %I::TEXT = %L', c.parent_filter, p_parent_tenant)
                                ELSE '' END)
               INTO v;
            IF v IS NULL THEN
                RAISE EXCEPTION '列 % の外部キーの先 % に、このテナントの行が無い', c.col, c.parent;
            END IF;
            v := format('%L::%s', v, c.typ);
        ELSIF c.check_val IS NOT NULL THEN
            v := quote_literal(c.check_val);
        ELSE
            v := CASE
                WHEN c.typ IN ('text', 'character varying') THEN 'md5(gen_random_uuid()::text)'
                WHEN c.typ = 'uuid' THEN 'gen_random_uuid()'
                WHEN c.typ IN ('smallint', 'integer', 'bigint', 'numeric', 'real', 'double precision') THEN '1'
                WHEN c.typ = 'boolean' THEN 'false'
                WHEN c.typ = 'date' THEN 'current_date'
                WHEN c.typ IN ('timestamp with time zone', 'timestamp without time zone') THEN 'now()'
                WHEN c.typ IN ('json', 'jsonb') THEN format('%L::%s', '{}', c.typ)
                WHEN c.typ = 'bytea' THEN $$'\x00'::bytea$$
            END;
            IF v IS NULL THEN
                RAISE EXCEPTION '列 % の型 % の値を作る規則が無い', c.col, c.typ;
            END IF;
        END IF;
        v_cols := v_cols || quote_ident(c.col);
        v_vals := v_vals || v;
    END LOOP;
    RETURN format('INSERT INTO %s (%s) VALUES (%s)', p_table::regclass,
                  array_to_string(v_cols, ', '), array_to_string(v_vals, ', '));
END
$fn$;

-- ---------------------------------------------------------------------------
-- 準備 (superuser)。対象の表をカタログから引き、テナント 2 つと、各表に A・B の行を入れる。
-- 準備に app.* の GUC を使わない (検査 a は、app.current_tenant_id を一度も設定していないことが前提)。
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_a        CONSTANT TEXT := gen_random_uuid()::TEXT;
    v_b        CONSTANT TEXT := gen_random_uuid()::TEXT;
    t          RECORD;
    v_sql      TEXT;
    v_progress INT;
    v_rows_a   BIGINT;
    v_rows_b   BIGINT;
BEGIN
    PERFORM set_config('chk.rls_t0', clock_timestamp()::TEXT, true),
            set_config('chk.rls_tenant_a', v_a, true),
            set_config('chk.rls_tenant_b', v_b, true);

    INSERT INTO chk_rls_rows (tbl, tbl_oid, read_open, write_open)
    SELECT c.relname, c.oid, coalesce(e.read_open, false), coalesce(e.write_open, false)
      FROM pg_class c
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
      LEFT JOIN chk_rls_exceptions e ON e.tbl = c.relname
     WHERE c.relnamespace = 'alc_api'::regnamespace
       AND c.relkind IN ('r', 'p');

    INSERT INTO alc_api.tenants (id, name)
    VALUES (v_a::UUID, 'ci check rls rows a'), (v_b::UUID, 'ci check rls rows b');

    LOOP
        v_progress := 0;
        FOR t IN SELECT r.tbl, r.tbl_oid FROM chk_rls_rows r WHERE NOT r.seeded ORDER BY r.tbl LOOP
            BEGIN
                EXECUTE pg_temp.chk_rls_insert_sql(t.tbl_oid, v_a, v_a);
                EXECUTE pg_temp.chk_rls_insert_sql(t.tbl_oid, v_b, v_b);
                v_sql := pg_temp.chk_rls_insert_sql(t.tbl_oid, v_b, v_a);
                UPDATE chk_rls_rows SET seeded = true, why = NULL, insert_b = v_sql WHERE tbl = t.tbl;
                v_progress := v_progress + 1;
            EXCEPTION WHEN OTHERS THEN
                -- A・B の片方だけ入った行は、この block の巻き戻しで消える
                UPDATE chk_rls_rows SET why = SQLSTATE || ' ' || SQLERRM WHERE tbl = t.tbl;
            END;
        END LOOP;
        EXIT WHEN v_progress = 0;
    END LOOP;

    -- INSERT が通っても、行が在るとは限らない (trigger が行を捨てる・tenant_id を書き換える)。
    -- A の行と B の行が実際に在る表だけを「行を入れた表」に数える
    FOR t IN SELECT r.tbl, r.tbl_oid FROM chk_rls_rows r WHERE r.seeded ORDER BY r.tbl LOOP
        EXECUTE format('SELECT count(*) FILTER (WHERE tenant_id::TEXT = %L),
                               count(*) FILTER (WHERE tenant_id::TEXT = %L)
                          FROM %s', v_a, v_b, t.tbl_oid::regclass)
           INTO v_rows_a, v_rows_b;
        IF v_rows_a < 1 OR v_rows_b < 1 THEN
            UPDATE chk_rls_rows
               SET seeded = false,
                   why = format('INSERT は通ったが、A の行 %s / B の行 %s', v_rows_a, v_rows_b)
             WHERE tbl = t.tbl;
        END IF;
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- 検査 a (alc_api_rt)。app.current_tenant_id を設定する前に、全部の表ぶんを流す
-- (一度でも設定すると、以後の「未設定」は 42704 ではなく空文字になる)。
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    t       RECORD;
    v_count BIGINT;
    v_state TEXT;
    v_msg   TEXT;
BEGIN
    IF coalesce(current_setting('app.current_tenant_id', true), '') <> '' THEN
        INSERT INTO chk_rls_violations
        VALUES ('a', 'session', 'app.current_tenant_id が設定済み (未設定の振る舞いを確かめられない)');
    END IF;

    FOR t IN SELECT r.tbl, r.tbl_oid, r.read_open FROM chk_rls_rows r WHERE r.seeded ORDER BY r.tbl LOOP
        v_count := NULL;
        v_state := NULL;
        SET LOCAL ROLE alc_api_rt;
        IF current_user <> 'alc_api_rt' THEN
            RAISE EXCEPTION 'alc_api_rt に切り替わっていない (current_user = %)', current_user;
        END IF;
        BEGIN
            EXECUTE format('SELECT count(*) FROM %s', t.tbl_oid::regclass) INTO v_count;
        EXCEPTION WHEN OTHERS THEN
            v_state := SQLSTATE;
            v_msg := SQLERRM;
        END;
        RESET ROLE;

        IF t.read_open THEN
            IF coalesce(v_count, 0) < 2 THEN
                INSERT INTO chk_rls_violations
                VALUES ('exception', 'table ' || t.tbl,
                        format('読みの例外が古い: テナント未設定の alc_api_rt から全部の行が見えるはずが、%s',
                               coalesce(v_count || ' 行', v_state || ' ' || v_msg)));
            END IF;
        ELSIF v_count > 0 THEN
            INSERT INTO chk_rls_violations
            VALUES ('a', 'table ' || t.tbl,
                    format('テナント未設定の alc_api_rt から %s 行読めた', v_count));
        ELSIF v_state IS NOT NULL AND v_state NOT IN ('42704', '22P02') THEN
            INSERT INTO chk_rls_violations
            VALUES ('a', 'table ' || t.tbl,
                    format('テナント未設定の alc_api_rt の SELECT が %s %s で落ちた (42704 / 22P02 / 0 行のどれでもない)',
                           v_state, v_msg));
        END IF;
        UPDATE chk_rls_rows SET a_done = true WHERE tbl = t.tbl;
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- 検査 b・c (alc_api_rt)。テナント A を設定する (worker の tenant_tx と同じ、transaction 単位の set_config)。
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_a     CONSTANT TEXT := current_setting('chk.rls_tenant_a');
    v_b     CONSTANT TEXT := current_setting('chk.rls_tenant_b');
    t       RECORD;
    v_own   BIGINT;
    v_other BIGINT;
    v_state TEXT;
    v_msg   TEXT;
    v_guc   TEXT;
BEGIN
    PERFORM set_config('app.current_tenant_id', v_a, true);

    FOR t IN
        SELECT r.tbl, r.tbl_oid, r.read_open, r.write_open, r.insert_b, e.guc, e.guc_col
          FROM chk_rls_rows r
          LEFT JOIN chk_rls_exceptions e ON e.tbl = r.tbl
         WHERE r.seeded
         ORDER BY r.tbl
    LOOP
        -- b
        v_own := NULL;
        v_other := NULL;
        v_state := NULL;
        SET LOCAL ROLE alc_api_rt;
        BEGIN
            EXECUTE format('SELECT count(*) FILTER (WHERE tenant_id::TEXT = %L),
                                   count(*) FILTER (WHERE tenant_id::TEXT IS DISTINCT FROM %L)
                              FROM %s', v_a, v_a, t.tbl_oid::regclass)
               INTO v_own, v_other;
        EXCEPTION WHEN OTHERS THEN
            v_state := SQLSTATE;
            v_msg := SQLERRM;
        END;
        RESET ROLE;

        IF v_state IS NOT NULL THEN
            INSERT INTO chk_rls_violations
            VALUES ('b', 'table ' || t.tbl,
                    format('テナント A を設定した alc_api_rt の SELECT が %s %s で落ちた', v_state, v_msg));
        ELSIF t.read_open THEN
            IF v_own < 1 OR v_other < 1 THEN
                INSERT INTO chk_rls_violations
                VALUES ('exception', 'table ' || t.tbl,
                        format('読みの例外が古い: テナント A から全部の行が見えるはずが、A の行 %s / A 以外の行 %s',
                               v_own, v_other));
            END IF;
        ELSE
            IF v_other > 0 THEN
                INSERT INTO chk_rls_violations
                VALUES ('b', 'table ' || t.tbl,
                        format('テナント A を設定した alc_api_rt から、A 以外の行が %s 行見える', v_other));
            END IF;
            IF v_own < 1 THEN
                INSERT INTO chk_rls_violations
                VALUES ('b', 'table ' || t.tbl,
                        'テナント A を設定した alc_api_rt から、A の行が見えない (空振り。分離を確かめられていない)');
            END IF;
        END IF;
        UPDATE chk_rls_rows SET b_done = true WHERE tbl = t.tbl;

        -- c
        v_state := NULL;
        v_guc := NULL;
        IF t.guc IS NOT NULL THEN
            -- 例外の表のポリシーが見る GUC に、INSERT する行の値 (A の行) を立てる
            EXECUTE format('SELECT %I::TEXT FROM %s WHERE tenant_id::TEXT = %L ORDER BY 1 LIMIT 1',
                           t.guc_col, t.tbl_oid::regclass, v_a)
               INTO v_guc;
            PERFORM set_config(t.guc, v_guc, true);
        END IF;
        SET LOCAL ROLE alc_api_rt;
        BEGIN
            EXECUTE t.insert_b;
        EXCEPTION WHEN OTHERS THEN
            v_state := SQLSTATE;
            v_msg := SQLERRM;
        END;
        RESET ROLE;
        IF t.guc IS NOT NULL THEN
            PERFORM set_config(t.guc, '', true);
        END IF;

        IF t.write_open THEN
            IF v_state IS NOT NULL THEN
                INSERT INTO chk_rls_violations
                VALUES ('exception', 'table ' || t.tbl,
                        format('書きの例外が古い: テナント A から B の tenant_id での INSERT が通るはずが、%s %s',
                               v_state, v_msg));
            END IF;
        ELSIF v_state IS NULL THEN
            INSERT INTO chk_rls_violations
            VALUES ('c', 'table ' || t.tbl,
                    'テナント A を設定した alc_api_rt から、B の tenant_id での INSERT が通った');
        ELSIF v_state <> '42501' THEN
            INSERT INTO chk_rls_violations
            VALUES ('c', 'table ' || t.tbl,
                    format('テナント A を設定した alc_api_rt から、B の tenant_id での INSERT が 42501 ではなく %s %s で落ちた (RLS が止めたとは言えない)',
                           v_state, v_msg));
        END IF;
        UPDATE chk_rls_rows SET c_done = true WHERE tbl = t.tbl;
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- 数の突き合わせ (superuser)。表の数は固定値で持たず、カタログから数え直す。
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_tables     BIGINT;
    v_seeded     BIGINT;
    v_ab         BIGINT;
    v_c          BIGINT;
    v_read_open  BIGINT;
    v_write_open BIGINT;
    v_names      TEXT;
BEGIN
    INSERT INTO chk_rls_violations
    SELECT 'seed', 'table ' || r.tbl, '行を入れられない — 種を足す (' || coalesce(r.why, '理由なし') || ')'
      FROM chk_rls_rows r
     WHERE NOT r.seeded;

    INSERT INTO chk_rls_violations
    SELECT 'seed', 'table ' || s.tbl, format('種が指す列 %s が無い (種が古い)', s.col)
      FROM chk_rls_seeds s
     WHERE NOT EXISTS (SELECT 1 FROM chk_rls_rows r
                         JOIN pg_attribute a ON a.attrelid = r.tbl_oid AND a.attname = s.col AND NOT a.attisdropped
                        WHERE r.tbl = s.tbl);

    INSERT INTO chk_rls_violations
    SELECT 'exception', 'table ' || e.tbl, '例外に載っているが、tenant_id を持つ表として在りません (例外が古い)'
      FROM chk_rls_exceptions e
     WHERE NOT EXISTS (SELECT 1 FROM chk_rls_rows r WHERE r.tbl = e.tbl);

    SELECT count(*) INTO v_tables
      FROM pg_class c
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped
     WHERE c.relnamespace = 'alc_api'::regnamespace
       AND c.relkind IN ('r', 'p');
    SELECT count(*) FILTER (WHERE e.read_open), count(*) FILTER (WHERE e.write_open)
      INTO v_read_open, v_write_open
      FROM chk_rls_exceptions e;
    SELECT count(*) FILTER (WHERE r.seeded),
           count(*) FILTER (WHERE r.seeded AND r.a_done AND r.b_done AND NOT r.read_open),
           count(*) FILTER (WHERE r.seeded AND r.c_done AND NOT r.write_open),
           string_agg(r.tbl, ' ' ORDER BY r.tbl)
               FILTER (WHERE r.seeded AND r.a_done AND r.b_done AND r.c_done AND NOT r.read_open AND NOT r.write_open)
      INTO v_seeded, v_ab, v_c, v_names
      FROM chk_rls_rows r;

    IF v_tables = 0 THEN
        INSERT INTO chk_rls_violations VALUES ('count', 'schema alc_api', 'tenant_id を持つ表が 1 つも在りません');
    END IF;
    IF v_ab <> v_tables - v_read_open THEN
        INSERT INTO chk_rls_violations
        VALUES ('count', 'schema alc_api',
                format('行を入れて a・b を確かめた表が %s (tenant_id を持つ表 %s − 例外 %s = %s のはず)',
                       v_ab, v_tables, v_read_open, v_tables - v_read_open));
    END IF;
    IF v_c <> v_tables - v_write_open THEN
        INSERT INTO chk_rls_violations
        VALUES ('count', 'schema alc_api',
                format('行を入れて c を確かめた表が %s (tenant_id を持つ表 %s − 例外 %s = %s のはず)',
                       v_c, v_tables, v_write_open, v_tables - v_write_open));
    END IF;

    RAISE NOTICE 'check_rls_rows: tenant_id を持つ表 % / 行を入れた表 % / a・b を確かめた表 % (例外 %) / c を確かめた表 % (例外 %) / 違反 % 行 / % 秒',
        v_tables, v_seeded, v_ab, v_read_open, v_c, v_write_open,
        (SELECT count(*) FROM chk_rls_violations),
        round(extract(epoch FROM clock_timestamp() - current_setting('chk.rls_t0')::TIMESTAMPTZ)::NUMERIC, 2);
    -- 例外の内訳。RLS が無効の表は読み・書きの両方の例外に数えているので、分けて出す
    RAISE NOTICE 'check_rls_rows: RLS 無効の例外: % / 読みの例外: % / 書きの例外: %',
        (SELECT format('%s 表 (%s)', count(*), string_agg(e.tbl, ' ' ORDER BY e.tbl))
           FROM chk_rls_exceptions e JOIN chk_rls_rows r ON r.tbl = e.tbl JOIN pg_class c ON c.oid = r.tbl_oid
          WHERE NOT c.relrowsecurity),
        (SELECT format('%s 表 (%s)', count(*), string_agg(e.tbl, ' ' ORDER BY e.tbl))
           FROM chk_rls_exceptions e JOIN chk_rls_rows r ON r.tbl = e.tbl JOIN pg_class c ON c.oid = r.tbl_oid
          WHERE c.relrowsecurity AND e.read_open),
        (SELECT format('%s 表 (%s)', count(*), string_agg(e.tbl, ' ' ORDER BY e.tbl))
           FROM chk_rls_exceptions e JOIN chk_rls_rows r ON r.tbl = e.tbl JOIN pg_class c ON c.oid = r.tbl_oid
          WHERE c.relrowsecurity AND e.write_open);
    RAISE NOTICE 'check_rls_rows: a・b・c の全部を行で確かめた表: %', v_names;
END
$$;

SELECT v.chk, v.object, v.detail
  FROM chk_rls_violations v
 ORDER BY v.chk, v.object, v.detail;
