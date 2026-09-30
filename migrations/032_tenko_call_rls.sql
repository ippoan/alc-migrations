-- tenko_call テーブルに RLS を有効化
ALTER TABLE tenko_call_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenko_call_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenko_call_numbers ENABLE ROW LEVEL SECURITY;

-- tenko_call_numbers: マスタは認証前に参照するため SELECT は全行許可、書き込みは tenant で制限
CREATE POLICY tenko_call_numbers_read ON tenko_call_numbers
    FOR SELECT USING (true);

CREATE POLICY tenko_call_numbers_write ON tenko_call_numbers
    FOR INSERT WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true));

CREATE POLICY tenko_call_numbers_update ON tenko_call_numbers
    FOR UPDATE USING (tenant_id = current_setting('app.current_tenant_id', true));

CREATE POLICY tenko_call_numbers_delete ON tenko_call_numbers
    FOR DELETE USING (tenant_id = current_setting('app.current_tenant_id', true));

-- tenko_call_drivers: phone_number 検索は set_config 前のため SELECT 許可、書き込みは tenant で制限
CREATE POLICY tenko_call_drivers_read ON tenko_call_drivers
    FOR SELECT USING (true);

CREATE POLICY tenko_call_drivers_insert ON tenko_call_drivers
    FOR INSERT WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true));

CREATE POLICY tenko_call_drivers_update ON tenko_call_drivers
    FOR UPDATE USING (tenant_id = current_setting('app.current_tenant_id', true));

CREATE POLICY tenko_call_drivers_delete ON tenko_call_drivers
    FOR DELETE USING (tenant_id = current_setting('app.current_tenant_id', true));

-- tenko_call_logs: tenant_id で行制限 (driver 経由)
CREATE POLICY tenko_call_logs_read ON tenko_call_logs
    FOR SELECT USING (driver_id IN (
        SELECT id FROM tenko_call_drivers
        WHERE tenant_id = current_setting('app.current_tenant_id', true)
    ));

CREATE POLICY tenko_call_logs_insert ON tenko_call_logs
    FOR INSERT WITH CHECK (driver_id IN (
        SELECT id FROM tenko_call_drivers
        WHERE tenant_id = current_setting('app.current_tenant_id', true)
    ));
