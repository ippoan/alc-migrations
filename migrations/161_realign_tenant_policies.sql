-- 9 表の RLS の policy と FORCE を、migration の履歴 (002・054・056) の定義に揃え直す。
-- 履歴どおりの DB では何も変わらない (冪等)。
-- 所有者で流す (DROP POLICY / ALTER TABLE は表の所有者でないと失敗する)。
-- Refs ippoan/auth-worker#605

SET LOCAL lock_timeout = '10s';

-- employees (002)
DROP POLICY IF EXISTS tenant_isolation_employees ON alc_api.employees;
CREATE POLICY tenant_isolation_employees ON alc_api.employees
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.employees NO FORCE ROW LEVEL SECURITY;

-- dtako_offices (054)
DROP POLICY IF EXISTS dtako_offices_tenant ON alc_api.dtako_offices;
CREATE POLICY dtako_offices_tenant ON alc_api.dtako_offices
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_offices NO FORCE ROW LEVEL SECURITY;

-- dtako_vehicles (054)
DROP POLICY IF EXISTS dtako_vehicles_tenant ON alc_api.dtako_vehicles;
CREATE POLICY dtako_vehicles_tenant ON alc_api.dtako_vehicles
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_vehicles NO FORCE ROW LEVEL SECURITY;

-- dtako_event_classifications (054)
DROP POLICY IF EXISTS dtako_event_cls_tenant ON alc_api.dtako_event_classifications;
CREATE POLICY dtako_event_cls_tenant ON alc_api.dtako_event_classifications
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_event_classifications NO FORCE ROW LEVEL SECURITY;

-- dtako_operations (054)
DROP POLICY IF EXISTS dtako_ops_tenant ON alc_api.dtako_operations;
CREATE POLICY dtako_ops_tenant ON alc_api.dtako_operations
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_operations NO FORCE ROW LEVEL SECURITY;

-- dtako_daily_work_hours (054)
DROP POLICY IF EXISTS dtako_dwh_tenant ON alc_api.dtako_daily_work_hours;
CREATE POLICY dtako_dwh_tenant ON alc_api.dtako_daily_work_hours
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_daily_work_hours NO FORCE ROW LEVEL SECURITY;

-- dtako_daily_work_segments (054)
DROP POLICY IF EXISTS dtako_dws_tenant ON alc_api.dtako_daily_work_segments;
CREATE POLICY dtako_dws_tenant ON alc_api.dtako_daily_work_segments
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_daily_work_segments NO FORCE ROW LEVEL SECURITY;

-- dtako_upload_history (054)
DROP POLICY IF EXISTS dtako_upload_tenant ON alc_api.dtako_upload_history;
CREATE POLICY dtako_upload_tenant ON alc_api.dtako_upload_history
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_upload_history NO FORCE ROW LEVEL SECURITY;

-- dtako_scrape_history (056)
DROP POLICY IF EXISTS dtako_scrape_history_tenant ON alc_api.dtako_scrape_history;
CREATE POLICY dtako_scrape_history_tenant ON alc_api.dtako_scrape_history
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);
ALTER TABLE alc_api.dtako_scrape_history NO FORCE ROW LEVEL SECURITY;

-- 事後の確認: 9 表それぞれで、ポリシーがちょうど 1 本・履歴の定義どおりで、RLS 有効・FORCE 無し。
-- 外れたら RAISE EXCEPTION で止める (同じ transaction なので、上の変更も戻る)。
-- メッセージに出すのは、表の名前・外れた条件・ポリシーの名前と command と本数だけ。
DO $$
DECLARE
    v_expected CONSTANT text[][] := ARRAY[
        ['employees',                   'tenant_isolation_employees'],
        ['dtako_offices',               'dtako_offices_tenant'],
        ['dtako_vehicles',              'dtako_vehicles_tenant'],
        ['dtako_event_classifications', 'dtako_event_cls_tenant'],
        ['dtako_operations',            'dtako_ops_tenant'],
        ['dtako_daily_work_hours',      'dtako_dwh_tenant'],
        ['dtako_daily_work_segments',   'dtako_dws_tenant'],
        ['dtako_upload_history',        'dtako_upload_tenant'],
        ['dtako_scrape_history',        'dtako_scrape_history_tenant']
    ];
    v_qual CONSTANT text := '(tenant_id = (current_setting(''app.current_tenant_id''::text))::uuid)';
    v_table text;
    v_name text;
    v_count int;
    v_list text[];
    v_ok boolean;
    v_rls boolean;
    v_force boolean;
BEGIN
    FOR i IN 1 .. array_length(v_expected, 1) LOOP
        v_table := v_expected[i][1];
        v_name := v_expected[i][2];

        SELECT count(*),
               array_agg(p.policyname || ' (' || p.cmd || ')' ORDER BY p.policyname),
               bool_and(p.policyname = v_name
                        AND p.cmd = 'ALL'
                        AND p.permissive = 'PERMISSIVE'
                        AND p.roles = '{public}'::name[]
                        AND p.with_check IS NULL
                        AND p.qual = v_qual)
          INTO v_count, v_list, v_ok
          FROM pg_policies p
         WHERE p.schemaname = 'alc_api'
           AND p.tablename = v_table;

        IF v_count <> 1 THEN
            RAISE EXCEPTION 'migration 161: alc_api.% のポリシーが 1 本ではない (% 本: %)',
                v_table, v_count, v_list;
        END IF;
        IF NOT v_ok THEN
            RAISE EXCEPTION 'migration 161: alc_api.% のポリシーが履歴の定義 (名前 %・ALL・PERMISSIVE・public・USING の式・WITH CHECK 無し) と違う (%)',
                v_table, v_name, v_list;
        END IF;

        SELECT c.relrowsecurity, c.relforcerowsecurity
          INTO v_rls, v_force
          FROM pg_class c
         WHERE c.oid = format('alc_api.%I', v_table)::regclass;

        IF NOT v_rls THEN
            RAISE EXCEPTION 'migration 161: alc_api.% が条件 (ROW LEVEL SECURITY 有効) を満たさない', v_table;
        END IF;
        IF v_force THEN
            RAISE EXCEPTION 'migration 161: alc_api.% が条件 (FORCE ROW LEVEL SECURITY 無し) を満たさない', v_table;
        END IF;
    END LOOP;
END
$$;
