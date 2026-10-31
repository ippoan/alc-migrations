-- 指静脈の記録を端末ごとに預かる (Refs ippoan/alc-app#558)
--
-- 同じ乗務員でも、撮った端末と違う端末では照合が通りにくい。その端末で撮った件を記録に入れると
-- 通る (2026-10-22・10-31 の実機)。乗務員がほかの端末で「この端末の指を足す」と、その端末で撮った
-- モジュールの記録 (base64) をここへ 1 行足す (同じ端末で撮り直したら差し替え)。端末へ配る記録は
-- worker が vein_templates の記録とここの記録から端末ごとに組む。行は全部残す (消すのは乗務員ごと)。
--
-- 承認は持たない (足したらすぐ使う。オーナー決定 2026-10-31)。足せるのは vein_templates に承認済みの
-- module の行がある乗務員だけで、それは worker が確かめる。
-- vein_templates と同じく開発用の端末 (app.device_dev) でも分けない (本人確認の素材は本番を共有する)。

CREATE TABLE alc_api.vein_device_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    employee_id UUID NOT NULL,
    -- 撮った端末 (端末の token の sub。vein_templates.registered_device_id と同じもの)
    device_id TEXT NOT NULL,
    -- モジュールの記録 (base64)。中身は worker も解釈しない (組み直しは vein-match)
    record TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT vein_device_records_employee_device_key UNIQUE (tenant_id, employee_id, device_id),
    CONSTRAINT vein_device_records_employee_id_fkey FOREIGN KEY (tenant_id, employee_id)
        REFERENCES alc_api.employees (tenant_id, id) ON DELETE CASCADE
);

ALTER TABLE alc_api.vein_device_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.vein_device_records FORCE ROW LEVEL SECURITY;
CREATE POLICY vein_device_records_tenant ON alc_api.vein_device_records
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.vein_device_records TO alc_api_app;
