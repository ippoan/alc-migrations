-- dev端末 (開発用の鍵) の記録を、その鍵でしか見えなくする
-- Refs ippoan/alc-app#387, ippoan/rust-alc-api#697
--
-- dev端末は本番環境でのテスト用の鍵。その鍵で行った点呼・測定・打刻の記録は、
-- 管理者ログインや本番の端末からは見えないようにする。
--
-- 鍵が dev かどうかは auth-worker が知っていて、検証済みの要求にだけ印を付けて
-- backend に渡す。backend は接続を取るたびに、テナント (app.current_tenant_id) と
-- 一緒に接続ごとの設定値 app.device_dev を立てる。この migration は DB 側で、
-- 対象の表に is_dev 列を足し、列の既定値と RLS をその設定値で決める。
-- backend の INSERT / SELECT は書き換えなくても、dev の行と本番の行が分かれる。
--
-- ---------------------------------------------------------------------------
-- 未設定 = dev でない
-- ---------------------------------------------------------------------------
-- dev 側に倒れるのは、設定値がちょうど '1' のときだけ。
--   coalesce(current_setting('app.device_dev', true), '') = '1'
-- 未設定 (NULL) も空文字も false になる。したがってこの migration の適用直後、
-- 設定値を立てない古い backend はそのまま動く — 既存の行 (全部 is_dev = false) が
-- 全部見え、書いた行は is_dev = false になる。
--
-- ---------------------------------------------------------------------------
-- 足すだけ (expand)
-- ---------------------------------------------------------------------------
-- 列・index を足し、ポリシーと関数を置き換えるだけで、消すものは無い。
-- hub_measurements の 3 列 unique (migration 126) も残す。古い backend は
-- ON CONFLICT (tenant_id, device_id, seq) でその制約を推論しているので、ここで
-- 4 列に置き換えると INSERT が全件落ちる。3 列を落とすのは、backend が 4 列へ
-- 切り替わって本番に出た後の別 migration で行う。
--
-- tenko_call_logs は対象外 (電話点呼の経路は端末の鍵を持たず dev になり得ない)。

-- 0. 前提の確認 (144 と同じ「沈黙しない」方針)。
--    下の ALTER POLICY は「各表のポリシーがこの 1 本だけ」であることに依存する。
--    ポリシーは OR で効くので、migration 履歴の外で別のポリシーが足されていると、
--    そちらを通って dev の行が見えてしまう。名前が違う・本数が違う場合は、
--    黙って穴を残さずここで落とす。
DO $$
DECLARE
    r       RECORD;
    v_names TEXT[];
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('tenko_sessions',             'tenant_isolation_tenko_sessions'),
            ('tenko_records',              'tenant_isolation_tenko_records'),
            ('measurements',               'tenant_isolation_measurements'),
            ('hub_measurements',           'hub_measurements_tenant'),
            ('webhook_deliveries',         'tenant_isolation_webhook_deliveries'),
            ('equipment_failures',         'tenant_isolation_equipment_failures'),
            ('tenko_carrying_item_checks', 'carrying_item_checks_tenant'),
            ('tenko_schedules',            'tenant_isolation_tenko_schedules')
        ) AS t(tbl, pol)
    LOOP
        SELECT coalesce(array_agg(p.policyname::TEXT ORDER BY p.policyname), '{}')
          INTO v_names
          FROM pg_policies p
         WHERE p.schemaname = 'alc_api'
           AND p.tablename = r.tbl;

        IF v_names <> ARRAY[r.pol] THEN
            RAISE EXCEPTION
                'migration 153: alc_api.% のポリシーが想定と違います (想定: {%} / 実際: %)。'
                ' migration 履歴の外でポリシーが足された・改名された可能性があります。'
                ' pg_policies を確認してから再実行してください。',
                r.tbl, r.pol, v_names;
        END IF;
    END LOOP;

    IF to_regprocedure('alc_api.set_current_tenant(text)') IS NULL THEN
        RAISE EXCEPTION
            'migration 153: alc_api.set_current_tenant(text) が見つかりません。'
            ' 関数が別のスキーマにある可能性があります。pg_proc を確認してから再実行してください。';
    END IF;
END
$$;

-- 1. is_dev 列。
--    2 段に分ける: 定数の既定値での ADD COLUMN は表を書き換えず、既存行への UPDATE にも
--    ならない (tenko_records には完了後の変更を禁じる trigger があり、既存行が UPDATE 扱いに
--    なる書き方だと落ちる)。既存行は全部 false になり、その後で既定値だけを式に差し替える。
--    index は足さない (dev の行はごく少数で、既存の tenant_id 始まりの index で足りる)。
ALTER TABLE alc_api.tenko_sessions ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.tenko_sessions ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.tenko_records ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.tenko_records ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.measurements ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.measurements ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.hub_measurements ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.hub_measurements ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.webhook_deliveries ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.webhook_deliveries ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.equipment_failures ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.equipment_failures ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.tenko_carrying_item_checks ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.tenko_carrying_item_checks ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

ALTER TABLE alc_api.tenko_schedules ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.tenko_schedules ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

-- 2. ポリシー。いまの式 (テナントの一致) はそのまま残し、is_dev の一致を AND で足す。
--    USING だけだったポリシーにも WITH CHECK を同じ式で明示する
--    (省略時は USING が使われるので意味は変わらない。書く行の検査を読んで分かるようにする)。
--    dev でない接続は is_dev = false の行だけ、dev の接続は is_dev = true の行だけを
--    読み書きできる。軸をまたぐ INSERT / UPDATE は WITH CHECK で拒否される。
ALTER POLICY tenant_isolation_tenko_sessions ON alc_api.tenko_sessions
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

ALTER POLICY tenant_isolation_tenko_records ON alc_api.tenko_records
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

ALTER POLICY tenant_isolation_measurements ON alc_api.measurements
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

ALTER POLICY hub_measurements_tenant ON alc_api.hub_measurements
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

ALTER POLICY tenant_isolation_webhook_deliveries ON alc_api.webhook_deliveries
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

ALTER POLICY tenant_isolation_equipment_failures ON alc_api.equipment_failures
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

-- tenko_carrying_item_checks は tenant_id を持たず、session 経由でテナントを引く (migration 055)。
ALTER POLICY carrying_item_checks_tenant ON alc_api.tenko_carrying_item_checks
    USING (
        session_id IN (SELECT id FROM alc_api.tenko_sessions WHERE tenant_id = current_setting('app.current_tenant_id')::UUID)
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        session_id IN (SELECT id FROM alc_api.tenko_sessions WHERE tenant_id = current_setting('app.current_tenant_id')::UUID)
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

ALTER POLICY tenant_isolation_tenko_schedules ON alc_api.tenko_schedules
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

-- 3. hub_measurements の再送冪等の鍵に is_dev を足した unique index を「足す」。
--    同じ端末の同じ seq が dev と本番の両方にあり得るようにするための土台。
--    既存の UNIQUE (tenant_id, device_id, seq) は残すので、この migration の時点では
--    まだ 3 列で弾かれる (backend が 4 列へ切り替わった後の別 migration で 3 列を落とす)。
--
--    CONCURRENTLY にしていないのは migration がトランザクション内で走るため (135 と同じ)。
CREATE UNIQUE INDEX hub_measurements_tenant_device_seq_is_dev
    ON alc_api.hub_measurements (tenant_id, device_id, seq, is_dev);

-- 4. set_current_tenant は毎回 dev の設定値を消す。
--    backend には SQL で直接 SELECT set_current_tenant($1) を呼ぶ経路があり、接続プールで
--    接続は使い回される。関数自体が消さないと、前の要求が立てた '1' が次の要求に残る。
--    dev の接続にしたい側は、この関数を呼んだ「後」に app.device_dev を立てる。
--
--    シグネチャ・戻り値・SECURITY DEFINER・search_path は migration 062 のまま
--    (CREATE OR REPLACE なので既存の権限も保たれる)。
CREATE OR REPLACE FUNCTION alc_api.set_current_tenant(tenant_id TEXT)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_tenant_id', tenant_id, false);
    PERFORM set_config('app.device_dev', '', false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = alc_api;
