-- CI の replay job 専用の検査。crate には含めない (scripts/ ではなく ci/ に置く)。
--
-- 子の表が外部キーで指す親の行が、子と同じテナントに在ることを、書き込みのポリシーが確かめていること
-- (migration 169・170) を、実行用ロール alc_api_rt から実際の行で確かめる。外部キーの検査は RLS を通らないので、
-- 子の tenant_id だけを見るポリシーでは、別のテナントの親の id を指す行が書けてしまう。Refs ippoan/rust-alc-api#747
--
-- 組ごとに、テナント A を設定した alc_api_rt から:
--   bad. A の子の行で、外部キーだけを B の親の行にした INSERT / UPDATE が 42501 (RLS の拒否) で落ちる
--        (成功も、42501 以外のエラーも違反)
--   ok.  同じ文で、外部キーを A の親の行にすると 1 行書ける (何でも拒否するポリシーを合格に数えない)
-- 組は列挙する (migration 169・170 の対象と同じ)。ci/check_rls_rows.sql の c (tenant_id だけを替える) では、
-- この穴は捕まらない。
--
-- 違反を 1 行ずつ返す (check, object, detail)。0 行なら合格。
-- このファイルは BEGIN / ROLLBACK を持たない。呼ぶ側が 1 transaction で包み、最後に ROLLBACK する
-- (DB には何も残らない)。接続は superuser (親の行を入れるのは superuser)。
-- ON_ERROR_STOP を外さない — 無いと SQL のエラーでも出力が空になり、合格に見える。
--
--   psql -v ON_ERROR_STOP=1 -q -At -F ' | ' -c BEGIN -f ci/check_rls_parent_tenant.sql -c ROLLBACK
--
-- id はその場で作る (実在の tenant_id は書かない)。

CREATE TEMP TABLE chk_pt_ids (
    tenant CHAR(1) NOT NULL,
    kind   TEXT NOT NULL,
    id     UUID NOT NULL,
    PRIMARY KEY (tenant, kind)
) ON COMMIT DROP;

CREATE TEMP TABLE chk_pt_violations (
    chk    TEXT NOT NULL,
    object TEXT NOT NULL,
    detail TEXT NOT NULL
) ON COMMIT DROP;

-- 親の行 (A・B の両方) と、UPDATE を試す A の子の行を superuser で入れる
DO $$
DECLARE
    v_tenant CHAR(1);
    v_t      UUID;
    v_id     UUID;
    v_ticket UUID;
BEGIN
    FOREACH v_tenant IN ARRAY ARRAY['A', 'B'] LOOP
        INSERT INTO alc_api.tenants (name) VALUES ('ci check rls parent tenant ' || v_tenant || ' ' || gen_random_uuid())
            RETURNING id INTO v_t;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'tenant', v_t);

        INSERT INTO alc_api.users (tenant_id, email, name, google_sub)
            VALUES (v_t, md5(gen_random_uuid()::text) || '@example.com', 'ci', md5(gen_random_uuid()::text))
            RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'user', v_id);

        INSERT INTO alc_api.employees (tenant_id, name) VALUES (v_t, 'ci') RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'employee', v_id);

        INSERT INTO alc_api.notify_recipients (tenant_id, name, provider, line_user_id)
            VALUES (v_t, 'ci', 'line', md5(gen_random_uuid()::text)) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'recipient', v_id);

        INSERT INTO alc_api.notify_groups (tenant_id, name) VALUES (v_t, md5(gen_random_uuid()::text)) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'group', v_id);

        INSERT INTO alc_api.notify_documents (tenant_id, r2_key) VALUES (v_t, md5(gen_random_uuid()::text)) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'document', v_id);

        INSERT INTO alc_api.trouble_workflow_states (tenant_id, name, label)
            VALUES (v_t, md5(gen_random_uuid()::text), 'ci') RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'state', v_id);
        INSERT INTO alc_api.trouble_workflow_states (tenant_id, name, label)
            VALUES (v_t, md5(gen_random_uuid()::text), 'ci') RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'state2', v_id);

        INSERT INTO alc_api.trouble_tickets (tenant_id, category) VALUES (v_t, 'ci') RETURNING id INTO v_ticket;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'ticket', v_ticket);

        INSERT INTO alc_api.trouble_tasks (tenant_id, ticket_id) VALUES (v_t, v_ticket) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'task', v_id);

        -- 勤怠 (migration 170)
        INSERT INTO alc_api.bot_configs (tenant_id, name, client_id, client_secret_encrypted, service_account, private_key_encrypted, bot_id)
            VALUES (v_t, 'ci', 'ci', 'ci', 'ci', 'ci', md5(gen_random_uuid()::text)) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'bot_config', v_id);

        INSERT INTO alc_api.lineworks_channels (tenant_id, bot_config_id, channel_id)
            VALUES (v_t, v_id, md5(gen_random_uuid()::text)) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'channel', v_id);

        INSERT INTO alc_api.leave_pages (tenant_id, r2_key, page_no, received_at)
            VALUES (v_t, md5(gen_random_uuid()::text), 1, now()) RETURNING id INTO v_id;
        INSERT INTO chk_pt_ids VALUES (v_tenant, 'leave_page', v_id);
    END LOOP;

    -- UPDATE を試す A の子の行 (親は全部 A)
    INSERT INTO alc_api.notify_deliveries (tenant_id, document_id, provider)
    SELECT (SELECT id FROM chk_pt_ids WHERE tenant = 'A' AND kind = 'tenant'),
           (SELECT id FROM chk_pt_ids WHERE tenant = 'A' AND kind = 'document'), 'line'
    RETURNING id INTO v_id;
    INSERT INTO chk_pt_ids VALUES ('A', 'delivery', v_id);

    -- leave_settings は tenant_id が主キー (1 テナント 1 行) なので、A の行 1 つを UPDATE で試す。
    -- leave_periods の UPDATE を試す A の行 (親は A の leave_page)
    INSERT INTO alc_api.leave_settings (tenant_id)
    SELECT id FROM chk_pt_ids WHERE tenant = 'A' AND kind = 'tenant';
    INSERT INTO alc_api.leave_periods (tenant_id, page_id, kind, start_date, end_date)
    SELECT (SELECT id FROM chk_pt_ids WHERE tenant = 'A' AND kind = 'tenant'),
           (SELECT id FROM chk_pt_ids WHERE tenant = 'A' AND kind = 'leave_page'), 'yukyu', current_date, current_date
    RETURNING id INTO v_id;
    INSERT INTO chk_pt_ids VALUES ('A', 'period', v_id);
END $$;

-- 組 (name, 文)。文の中の {X} は A の行の id に置き換える (X は chk_pt_ids.kind)。
-- 確かめる外部キーの値 {P} には、bad は B の親、ok は A の親の id が入る (parent = 親の kind)。
-- 組どうしの ok の行が一意制約で当たらないよう、transitions は state と state2 の組を逆向きに使う。
CREATE TEMP TABLE chk_pt_cases (
    name   TEXT PRIMARY KEY,
    parent TEXT NOT NULL,
    stmt   TEXT NOT NULL
) ON COMMIT DROP;

INSERT INTO chk_pt_cases (name, parent, stmt) VALUES
    ('notify_recipient_groups.recipient_id', 'recipient',
     'INSERT INTO alc_api.notify_recipient_groups (group_id, recipient_id) VALUES ({group}, {P})'),
    ('notify_deliveries.document_id (INSERT)', 'document',
     'INSERT INTO alc_api.notify_deliveries (tenant_id, document_id, provider) VALUES ({tenant}, {P}, ''line'')'),
    ('notify_deliveries.recipient_id (INSERT)', 'recipient',
     'INSERT INTO alc_api.notify_deliveries (tenant_id, document_id, provider, recipient_id) VALUES ({tenant}, {document}, ''line'', {P})'),
    ('notify_deliveries.triggered_by_user_id (INSERT)', 'user',
     'INSERT INTO alc_api.notify_deliveries (tenant_id, document_id, provider, triggered_by_user_id) VALUES ({tenant}, {document}, ''line'', {P})'),
    ('notify_deliveries.document_id (UPDATE)', 'document',
     'UPDATE alc_api.notify_deliveries SET document_id = {P} WHERE id = {delivery}'),
    ('notify_deliveries.recipient_id (UPDATE)', 'recipient',
     'UPDATE alc_api.notify_deliveries SET recipient_id = {P} WHERE id = {delivery}'),
    ('trouble_tickets.status_id', 'state',
     'INSERT INTO alc_api.trouble_tickets (tenant_id, category, status_id) VALUES ({tenant}, ''ci'', {P})'),
    ('trouble_tickets.person_id', 'employee',
     'INSERT INTO alc_api.trouble_tickets (tenant_id, category, person_id) VALUES ({tenant}, ''ci'', {P})'),
    ('trouble_tasks.ticket_id (INSERT)', 'ticket',
     'INSERT INTO alc_api.trouble_tasks (tenant_id, ticket_id) VALUES ({tenant}, {P})'),
    ('trouble_tasks.ticket_id (UPDATE)', 'ticket',
     'UPDATE alc_api.trouble_tasks SET ticket_id = {P} WHERE id = {task}'),
    ('trouble_files.ticket_id', 'ticket',
     'INSERT INTO alc_api.trouble_files (tenant_id, ticket_id, filename, storage_key) VALUES ({tenant}, {P}, ''ci'', ''ci'')'),
    ('trouble_files.task_id', 'task',
     'INSERT INTO alc_api.trouble_files (tenant_id, ticket_id, task_id, filename, storage_key) VALUES ({tenant}, {ticket}, {P}, ''ci'', ''ci'')'),
    ('trouble_schedules.ticket_id', 'ticket',
     'INSERT INTO alc_api.trouble_schedules (tenant_id, ticket_id, scheduled_at, message) VALUES ({tenant}, {P}, now(), ''ci'')'),
    ('trouble_status_history.ticket_id', 'ticket',
     'INSERT INTO alc_api.trouble_status_history (tenant_id, ticket_id, to_state_id) VALUES ({tenant}, {P}, {state})'),
    ('trouble_status_history.from_state_id', 'state',
     'INSERT INTO alc_api.trouble_status_history (tenant_id, ticket_id, from_state_id, to_state_id) VALUES ({tenant}, {ticket}, {P}, {state})'),
    ('trouble_status_history.to_state_id', 'state',
     'INSERT INTO alc_api.trouble_status_history (tenant_id, ticket_id, to_state_id) VALUES ({tenant}, {ticket}, {P})'),
    ('trouble_workflow_transitions.from_state_id', 'state',
     'INSERT INTO alc_api.trouble_workflow_transitions (tenant_id, from_state_id, to_state_id) VALUES ({tenant}, {P}, {state2})'),
    ('trouble_workflow_transitions.to_state_id', 'state',
     'INSERT INTO alc_api.trouble_workflow_transitions (tenant_id, from_state_id, to_state_id) VALUES ({tenant}, {state2}, {P})'),
    -- 勤怠 (170)。leave_settings は CHECK leave_settings_single_destination (lineworks_channel_id と notify_recipient_id は
    -- 同時に非 NULL 不可) があり、ok で書いた値が次の組に残るので、試す列以外は同じ文で NULL に戻す
    ('leave_settings.lineworks_channel_id', 'channel',
     'UPDATE alc_api.leave_settings SET lineworks_channel_id = {P}, notify_recipient_id = NULL, notify_bot_config_id = NULL WHERE tenant_id = {tenant}'),
    ('leave_settings.notify_recipient_id', 'recipient',
     'UPDATE alc_api.leave_settings SET lineworks_channel_id = NULL, notify_recipient_id = {P}, notify_bot_config_id = NULL WHERE tenant_id = {tenant}'),
    ('leave_settings.notify_bot_config_id', 'bot_config',
     'UPDATE alc_api.leave_settings SET lineworks_channel_id = NULL, notify_recipient_id = NULL, notify_bot_config_id = {P} WHERE tenant_id = {tenant}'),
    ('leave_periods.page_id (INSERT)', 'leave_page',
     'INSERT INTO alc_api.leave_periods (tenant_id, page_id, kind, start_date, end_date) VALUES ({tenant}, {P}, ''yukyu'', current_date, current_date)'),
    ('leave_periods.page_id (UPDATE)', 'leave_page',
     'UPDATE alc_api.leave_periods SET page_id = {P} WHERE id = {period}');

DO $$
DECLARE
    v_case  RECORD;
    v_id    RECORD;
    v_mode  TEXT;
    v_sql   TEXT;
    v_state TEXT;
    v_msg   TEXT;
    v_rows  BIGINT;
BEGIN
    PERFORM set_config('app.current_tenant_id', (SELECT id::TEXT FROM chk_pt_ids WHERE tenant = 'A' AND kind = 'tenant'), true);

    FOR v_case IN SELECT * FROM chk_pt_cases ORDER BY name LOOP
        -- bad を先に流す (ok が先だと、主キーの重複など RLS 以外の理由で bad が落ちうる)
        FOREACH v_mode IN ARRAY ARRAY['bad', 'ok'] LOOP
            v_sql := replace(v_case.stmt, '{P}', quote_literal(
                (SELECT id FROM chk_pt_ids
                  WHERE tenant = CASE v_mode WHEN 'bad' THEN 'B' ELSE 'A' END AND kind = v_case.parent)::TEXT));
            FOR v_id IN SELECT kind, id FROM chk_pt_ids WHERE tenant = 'A' LOOP
                v_sql := replace(v_sql, '{' || v_id.kind || '}', quote_literal(v_id.id::TEXT));
            END LOOP;
            IF v_sql ~ '\{' THEN
                RAISE EXCEPTION '組 % の文に置き換えられない {…} が残っている: %', v_case.name, v_sql;
            END IF;

            v_state := NULL;
            v_rows := NULL;
            BEGIN
                SET LOCAL ROLE alc_api_rt;
                IF current_user <> 'alc_api_rt' THEN
                    RAISE EXCEPTION 'alc_api_rt に切り替わっていない (current_user = %)', current_user;
                END IF;
                EXECUTE v_sql;
                GET DIAGNOSTICS v_rows = ROW_COUNT;
                RESET ROLE;
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
            END;

            IF v_mode = 'bad' THEN
                IF v_state IS NULL THEN
                    INSERT INTO chk_pt_violations VALUES ('bad', v_case.name,
                        format('テナント A の alc_api_rt から、テナント B の親 (%s) を指す書き込みが通った (%s 行)', v_case.parent, v_rows));
                ELSIF v_state <> '42501' THEN
                    INSERT INTO chk_pt_violations VALUES ('bad', v_case.name,
                        format('B の親を指す書き込みが 42501 ではなく %s %s で落ちた (RLS が止めたとは言えない)', v_state, v_msg));
                END IF;
            ELSE
                IF v_state IS NOT NULL THEN
                    INSERT INTO chk_pt_violations VALUES ('ok', v_case.name,
                        format('A の親を指す書き込みが %s %s で落ちた', v_state, v_msg));
                ELSIF v_rows <> 1 THEN
                    INSERT INTO chk_pt_violations VALUES ('ok', v_case.name,
                        format('A の親を指す書き込みが 1 行ではなく %s 行', v_rows));
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'check_rls_parent_tenant: % 組を確かめた', (SELECT count(*) FROM chk_pt_cases);
END $$;

SELECT chk, object, detail FROM chk_pt_violations ORDER BY chk, object;
