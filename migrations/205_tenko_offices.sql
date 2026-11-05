-- 点呼の営業所と、車両・運行管理者の所属営業所 (足すだけ)
--
-- 血圧の記録が足りず対面点呼に切り替えた業務前の点呼 (ippoan/alc-app#626) で、運行管理者の判定のときに点呼の方法を
-- 所属で決める。点呼の営業所は車両で決まり、判定した運行管理者の所属営業所と比べる。
-- 同じ営業所なら対面点呼 (通常点呼)、別の営業所・グループ企業なら告示 266 号 第四条 2 項により遠隔点呼とみなす。
-- 読み書きは alc-tenko-worker (`/api/tenko/offices`)、判定は alc-measurements-worker。
--
-- 1. tenko_offices: テナントの点呼の営業所・車庫。company_name が NULL なら自社、入っていればグループ企業の営業所。
--    グループ企業の運行管理者もこのテナントの社員として登録して判定する (判定できるのは同じテナントの社員だけ)ので、
--    別テナントとは紐づけない。届出の様式に差し込む tenko_filing_settings.offices (201) とは別に持つ
-- 2. tenko_office_managers: 運行管理者の所属営業所 (兼務があるので社員と営業所の多対多)
-- 3. maintenance_vehicles.office_id: 車両の所属営業所。車両 identity の正本 (147) に持たせる。
--    点呼のセッションの vehicle_number と registration_number を照合して引く
--
-- 外部キーは (tenant_id, <列>) の複合にする (172)。営業所を消すと所属は外れる (車両は SET NULL (office_id))。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。alc_api_rt へは 158 の
-- ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

-- 1. tenko_offices
CREATE TABLE alc_api.tenko_offices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (btrim(name) <> ''),
    company_name TEXT NULL,
    address TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenko_offices_tenant_id_id_key UNIQUE (tenant_id, id)
);

ALTER TABLE alc_api.tenko_offices ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_offices FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_offices_tenant ON alc_api.tenko_offices
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_offices TO alc_api_app;

-- 2. tenko_office_managers
CREATE TABLE alc_api.tenko_office_managers (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    office_id UUID NOT NULL,
    employee_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, office_id, employee_id),
    CONSTRAINT tenko_office_managers_office_id_fkey FOREIGN KEY (tenant_id, office_id)
        REFERENCES alc_api.tenko_offices (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT tenko_office_managers_employee_id_fkey FOREIGN KEY (tenant_id, employee_id)
        REFERENCES alc_api.employees (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_tenko_office_managers_employee
    ON alc_api.tenko_office_managers (tenant_id, employee_id);

ALTER TABLE alc_api.tenko_office_managers ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_office_managers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_office_managers_tenant ON alc_api.tenko_office_managers
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_office_managers TO alc_api_app;

-- 3. maintenance_vehicles.office_id
ALTER TABLE alc_api.maintenance_vehicles ADD COLUMN office_id UUID NULL;
ALTER TABLE alc_api.maintenance_vehicles ADD CONSTRAINT maintenance_vehicles_office_id_fkey
    FOREIGN KEY (tenant_id, office_id) REFERENCES alc_api.tenko_offices (tenant_id, id) ON DELETE SET NULL (office_id);
