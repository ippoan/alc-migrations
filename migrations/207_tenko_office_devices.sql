-- 点呼端末の所属営業所 (足すだけ)
--
-- キオスクの車両番号の入力で、端末の営業所の車両を候補の上に出すため、点呼端末を 205 の点呼の営業所に所属させる。
-- 設定は管理画面 (alc-app の「点呼の営業所」)、読み書きは alc-tenko-worker、候補は alc-measurements-worker。
-- 判定 (点呼の方法) には使わない (点呼の営業所は車両で決まる)。
--
-- * device_id: 端末の鍵の登録簿 (auth-worker) の端末 ID。auth-worker が要求に付ける `X-Device-Id` と同じ値。
--   登録簿は別の DB に在るので外部キーは張らない
-- * 1 台は 1 営業所 (主キー)。営業所を消すと所属も消える
--
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。alc_api_rt へは 158 の
-- ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

CREATE TABLE alc_api.tenko_office_devices (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL CHECK (device_id ~ '^[A-Za-z0-9:_-]{1,64}$'),
    office_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, device_id),
    CONSTRAINT tenko_office_devices_office_id_fkey FOREIGN KEY (tenant_id, office_id)
        REFERENCES alc_api.tenko_offices (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_tenko_office_devices_office
    ON alc_api.tenko_office_devices (tenant_id, office_id);

ALTER TABLE alc_api.tenko_office_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_office_devices FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_office_devices_tenant ON alc_api.tenko_office_devices
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_office_devices TO alc_api_app;
