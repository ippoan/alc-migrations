-- CI の replay job 専用の検査 (migration 178)。crate には含めない。
--
-- notify_recipients の provider に 'email' が入ること (069 の自動名の CHECK を 178 が取り替えられたこと) と、
-- メールもメッセージング ID も無い 'email' の行・provider 'sms' の行・provider が 'line' でメールだけの行は
-- 弾かれること (check_violation) を確かめる。1 transaction で流して ROLLBACK するので、DB には何も残らない。
-- tenant はその場で作る (実在の id は書かない)。
--
--   psql -v ON_ERROR_STOP=1 -f ci/check_notify_recipients_email.sql

\set ON_ERROR_STOP on
SET plpgsql.check_asserts = on;

BEGIN;

INSERT INTO alc_api.tenants (id, name) VALUES (gen_random_uuid(), 'ci check email provider');

DO $$
DECLARE
    t UUID := (SELECT id FROM alc_api.tenants WHERE name = 'ci check email provider');
    c TEXT;
BEGIN
    -- 通る: メールだけの宛先 / 従来の宛先
    INSERT INTO alc_api.notify_recipients (tenant_id, name, provider, email)
    VALUES (t, 'email only', 'email', 'a@example.invalid');
    INSERT INTO alc_api.notify_recipients (tenant_id, name, provider, line_user_id)
    VALUES (t, 'line', 'line', 'chk-line');
    INSERT INTO alc_api.notify_recipients (tenant_id, name, provider, lineworks_user_id)
    VALUES (t, 'lineworks', 'lineworks', 'chk-lw');

    -- 弾かれる: (名前, provider, email) の組。ID は全部 NULL
    FOR c IN
        SELECT unnest(ARRAY['email:NULL', 'email:blank', 'sms:mail', 'line:mail'])
    LOOP
        BEGIN
            INSERT INTO alc_api.notify_recipients (tenant_id, name, provider, email)
            VALUES (
                t, c,
                split_part(c, ':', 1),
                CASE split_part(c, ':', 2) WHEN 'NULL' THEN NULL WHEN 'blank' THEN '  ' ELSE 'b@example.invalid' END
            );
            RAISE EXCEPTION '弾かれるはずの行が入った: %', c;
        EXCEPTION WHEN check_violation THEN
            NULL;
        END;
    END LOOP;

    ASSERT (SELECT count(*) FROM alc_api.notify_recipients WHERE tenant_id = t) = 3,
        'ci check の宛先は 3 行のはず';
END
$$;

ROLLBACK;
