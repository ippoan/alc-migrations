-- 自動点呼機器の認定要件 (様式3-1 業務前・様式3-2 業務後) の不足を埋める (足すだけ)
--
-- 1. tenko_records の改ざん防止を 015 の強さに戻す (業務前 二十二 / 業務後 十三)。
--    062 で関数の本文が「status = 'completed' の行だけ例外」に変わり、中止 (cancelled)・中断 (interrupted) の
--    記録は UPDATE で書き換えられた (DELETE は RETURN NEW = NULL で黙って飛ばされていた)。全ての行で例外にする。
-- 2. 機器故障 (equipment_failures) の変更前の行を履歴に残し、削除を止める (業務前 二十一・二十二 / 業務後 十二・十三)。
--    解決の記録 (PUT) は残すので UPDATE は止めず、変更のたびに変更前の行を equipment_failure_history へ写す。
--    履歴は UPDATE も DELETE もできない。
-- 3. 点呼の設定 tenko_settings (テナントに 1 行)。予定超過とする分数 overdue_minutes (業務前 十九 / 業務後 十)。
--    行が無いテナントは worker が既定の 60 分で動く。読み書きは alc-tenko-worker。
-- 4. 列を足す。
--    * tenko_schedules.vehicle_number / tenko_sessions.vehicle_number・vehicle_number_source:
--      自動車登録番号又は車両番号 (業務前 二十 ハ / 業務後 十一 ハ)。source は carins (車検証の読取) /
--      schedule (予定の値) / manual (キオスクで入力)
--    * tenko_sessions.resumed_by_name: 再開の判断を行った運行管理者の氏名 (業務前 二十 ヨ)
--    * tenko_sessions.alternative_measure: 運行に従事できないと判断した場合の代替措置の内容 (業務前 二十 タ)
--    tenko_records には列を足さない。セッションの全体が record_data に入り、CSV はそこから読む (142 と同じ)。
--
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。alc_api_rt へは 158 の
-- ALTER DEFAULT PRIVILEGES で付くので書かない。

-- 1. tenko_records
CREATE OR REPLACE FUNCTION alc_api.prevent_tenko_record_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'tenko_records cannot be modified or deleted (tamper prevention)';
END;
$$ LANGUAGE plpgsql SET search_path = alc_api;

-- 2. equipment_failures
CREATE TABLE alc_api.equipment_failure_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    failure_id UUID NOT NULL,
    old_row JSONB NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_dev BOOLEAN NOT NULL DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1')
);
CREATE INDEX idx_equipment_failure_history_failure
    ON alc_api.equipment_failure_history (tenant_id, failure_id, changed_at);

ALTER TABLE alc_api.equipment_failure_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.equipment_failure_history FORCE ROW LEVEL SECURITY;
CREATE POLICY equipment_failure_history_tenant ON alc_api.equipment_failure_history
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );
GRANT SELECT, INSERT ON alc_api.equipment_failure_history TO alc_api_app;

CREATE FUNCTION alc_api.keep_equipment_failure_history()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO alc_api.equipment_failure_history (tenant_id, failure_id, old_row, is_dev)
    VALUES (OLD.tenant_id, OLD.id, to_jsonb(OLD), OLD.is_dev);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = alc_api;

CREATE FUNCTION alc_api.prevent_equipment_failure_deletion()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION '% cannot be deleted (tamper prevention)', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql SET search_path = alc_api;

CREATE FUNCTION alc_api.prevent_equipment_failure_history_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'equipment_failure_history cannot be modified or deleted (tamper prevention)';
END;
$$ LANGUAGE plpgsql SET search_path = alc_api;

CREATE TRIGGER trg_keep_equipment_failure_history
    BEFORE UPDATE ON alc_api.equipment_failures
    FOR EACH ROW EXECUTE FUNCTION alc_api.keep_equipment_failure_history();
CREATE TRIGGER trg_prevent_equipment_failure_delete
    BEFORE DELETE ON alc_api.equipment_failures
    FOR EACH ROW EXECUTE FUNCTION alc_api.prevent_equipment_failure_deletion();
CREATE TRIGGER trg_prevent_equipment_failure_history_update
    BEFORE UPDATE ON alc_api.equipment_failure_history
    FOR EACH ROW EXECUTE FUNCTION alc_api.prevent_equipment_failure_history_modification();
CREATE TRIGGER trg_prevent_equipment_failure_history_delete
    BEFORE DELETE ON alc_api.equipment_failure_history
    FOR EACH ROW EXECUTE FUNCTION alc_api.prevent_equipment_failure_history_modification();

-- 3. tenko_settings
CREATE TABLE alc_api.tenko_settings (
    tenant_id UUID PRIMARY KEY REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    overdue_minutes INTEGER NOT NULL DEFAULT 60 CHECK (overdue_minutes BETWEEN 1 AND 1440),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE alc_api.tenko_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_settings_tenant ON alc_api.tenko_settings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_settings TO alc_api_app;

-- 4. 列
ALTER TABLE alc_api.tenko_schedules ADD COLUMN vehicle_number TEXT NULL;
ALTER TABLE alc_api.tenko_sessions ADD COLUMN vehicle_number TEXT NULL;
ALTER TABLE alc_api.tenko_sessions ADD COLUMN vehicle_number_source TEXT NULL
    CHECK (vehicle_number_source IN ('carins', 'schedule', 'manual'));
ALTER TABLE alc_api.tenko_sessions ADD COLUMN resumed_by_name TEXT NULL;
ALTER TABLE alc_api.tenko_sessions ADD COLUMN alternative_measure TEXT NULL;
