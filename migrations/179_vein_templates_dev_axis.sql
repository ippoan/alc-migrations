-- 指静脈テンプレート (vein_templates) を dev端末の軸で分ける (expand)
-- Refs ippoan/vein-match#20, ippoan/alc-app#387
--
-- migration 153 は点呼・測定の 8 表を is_dev 列と RLS で本番の行から分けたが、
-- vein_templates (migration 151) は対象外だった。開発用の鍵で指静脈を登録しても
-- 本番の行に入ってしまうので、153 と同じ書き方でこの 1 表も分ける。
-- 鍵が dev かどうかの扱い (app.device_dev、未設定 = dev でない) は 153 のコメントのとおり。
--
-- ---------------------------------------------------------------------------
-- 3 段で進める (この migration は 1 段目)
-- ---------------------------------------------------------------------------
--   1. この migration: is_dev 列・ポリシー・(tenant_id, employee_id, is_dev) の unique index を「足す」。
--   2. alc-vein-worker を 3 列の ON CONFLICT (tenant_id, employee_id, is_dev) に切り替えて本番に出す。
--   3. 151 の UNIQUE (tenant_id, employee_id) を落とす (別 migration、contract)。
--
-- 151 の 2 列 UNIQUE はここでは残す。旧 alc-vein-worker は
-- ON CONFLICT (tenant_id, employee_id) でこの制約を推論しているので、今落とすと
-- 切り替わるまでの登録が全件落ちる。したがって、この migration の時点では
-- 同じ乗務員の dev の行と本番の行はまだ両立しない (2 列で弾かれる)。
-- 両立するのは 3 段目の後。
--
-- 適用直後、設定値を立てない旧 worker はそのまま動く (既存の行は全部 is_dev = false、
-- 書いた行も false)。
--
-- 表が 1 つなので 155 のように index を別ファイルにはしない
-- (155 が分けたのは 153 が 8 表に ACCESS EXCLUSIVE を取るため。ここで待たされるのは
-- vein_templates への書き込みだけで、行数は乗務員の数)。
-- CONCURRENTLY にしていないのは migration が transaction 内で走るため (135 と同じ)。

SET LOCAL lock_timeout = '10s';

-- 0. 前提の確認 (153 と同じ「沈黙しない」方針)。
--    下の ALTER POLICY は「RLS が有効で、ポリシーが tenant_isolation_vein_templates
--    (全コマンド用) の 1 本だけ」であることに依存する。違えば黙って穴を残さず落とす。
DO $$
DECLARE
    v_rls    BOOLEAN;
    v_count  INT;
    v_found  TEXT[];
BEGIN
    v_rls := NULL;
    SELECT c.relrowsecurity
      INTO v_rls
      FROM pg_class c
     WHERE c.oid = to_regclass('alc_api.vein_templates');

    IF v_rls IS NOT TRUE THEN
        RAISE EXCEPTION
            'migration 179: alc_api.vein_templates で RLS が有効になっていません (表が alc_api に無い場合も含む)。'
            ' RLS が無効だとポリシーを直しても dev の行は分離されません。'
            ' pg_class.relrowsecurity を確認してから再実行してください。';
    END IF;

    SELECT count(*),
           coalesce(array_agg(format('%s (%s)', p.policyname, p.cmd) ORDER BY p.policyname), '{}')
      INTO v_count, v_found
      FROM pg_policies p
     WHERE p.schemaname = 'alc_api'
       AND p.tablename = 'vein_templates';

    IF v_count <> 1 OR v_found <> ARRAY['tenant_isolation_vein_templates (ALL)'] THEN
        RAISE EXCEPTION
            'migration 179: alc_api.vein_templates のポリシーが % 本見つかりました: % (想定は "tenant_isolation_vein_templates (ALL)" の 1 本だけ)。'
            ' migration 履歴の外でポリシーが足された・改名された・コマンド別に張り直された可能性があります。'
            ' pg_policies を確認してから再実行してください。',
            v_count, v_found;
    END IF;
END
$$;

-- 1. is_dev 列 (153 と同じ 2 段。既存行は全部 false)。
ALTER TABLE alc_api.vein_templates ADD COLUMN is_dev BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.vein_templates ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

-- 2. ポリシー。151 の式 (テナントの一致) は残し、is_dev の一致を AND で足す。
ALTER POLICY tenant_isolation_vein_templates ON alc_api.vein_templates
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );

-- 3. 新 worker の ON CONFLICT (tenant_id, employee_id, is_dev) が推論する unique index。
CREATE UNIQUE INDEX vein_templates_tenant_employee_is_dev
    ON alc_api.vein_templates (tenant_id, employee_id, is_dev);
