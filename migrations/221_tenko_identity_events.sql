-- 点呼の本人確認 (指静脈の照合) の記録 (足すだけ。Refs ippoan/alc-app#720, #676)
--
-- 自己点検表 ト①「生体認証をする時の顔の画像」。点呼の開始と再開の本人確認のとき、照合した端末・時刻・方法と、
-- 端末のカメラで撮った顔写真 (撮れたとき) を 1 行残す。端末に監視カメラ (alc-cam) を結び付けている拠点では、
-- alc-cam がこの時刻の前後を切り出す (cam_clip_events.source_table = 'tenko_identity_events')。どちらで顔を残すかは
-- カメラの配置で決まる (端末のカメラが在れば写真、監視カメラを結び付けていれば切り出し。両方なら両方)。
--
-- tenko_identity_events: 本人確認 1 回 = 1 行。書くのは alc-measurements-worker (開始・自分での再開)。
--   phase は start (開始) / resume (運行管理者が再開した点呼を運転者が続けるとき)。
--   device_id は照合した端末 (端末の token の sub。measurements.device_id と同じもの。管理者の画面からは NULL)。
--   face_photo_url は端末のカメラで撮った顔写真 (撮れなければ NULL)。
--   書き換え・削除は trigger で拒む (追記だけ。点呼の記録と同じ)。
--
-- tenko_records と同じく is_dev の軸を持つ (153)。外部キーは (tenant_id, <列>) の複合にする (172)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

CREATE TABLE alc_api.tenko_identity_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    session_id UUID NOT NULL,
    employee_id UUID NOT NULL,
    phase TEXT NOT NULL CHECK (phase IN ('start', 'resume')),
    method TEXT NULL,
    device_id TEXT NULL,
    face_photo_url TEXT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_dev BOOLEAN NOT NULL DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenko_identity_events_tenant_id_id_key UNIQUE (tenant_id, id),
    CONSTRAINT tenko_identity_events_session_id_fkey FOREIGN KEY (tenant_id, session_id)
        REFERENCES alc_api.tenko_sessions (tenant_id, id),
    CONSTRAINT tenko_identity_events_employee_id_fkey FOREIGN KEY (tenant_id, employee_id)
        REFERENCES alc_api.employees (tenant_id, id)
);
CREATE INDEX idx_tenko_identity_events_session
    ON alc_api.tenko_identity_events (tenant_id, session_id, occurred_at);
-- alc-cam の切り出し: 端末ごとの本人確認を時刻で引く
CREATE INDEX idx_tenko_identity_events_device
    ON alc_api.tenko_identity_events (tenant_id, device_id, occurred_at)
    WHERE device_id IS NOT NULL;

ALTER TABLE alc_api.tenko_identity_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_tenko_identity_events ON alc_api.tenko_identity_events
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_identity_events TO alc_api_app;

-- 改ざん防止: 追記だけ (UPDATE / DELETE を拒む)
CREATE FUNCTION alc_api.prevent_tenko_identity_event_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = alc_api
AS $$
BEGIN
    RAISE EXCEPTION 'tenko_identity_events cannot be modified or deleted (tamper prevention)';
END;
$$;

CREATE TRIGGER trg_prevent_tenko_identity_event_update
    BEFORE UPDATE ON alc_api.tenko_identity_events
    FOR EACH ROW
    EXECUTE FUNCTION alc_api.prevent_tenko_identity_event_modification();

CREATE TRIGGER trg_prevent_tenko_identity_event_delete
    BEFORE DELETE ON alc_api.tenko_identity_events
    FOR EACH ROW
    EXECUTE FUNCTION alc_api.prevent_tenko_identity_event_modification();

-- 監視カメラの切り出しの元に本人確認を足す (190 の 4 つ + tenko_identity_events)
ALTER TABLE alc_api.cam_clip_events DROP CONSTRAINT cam_clip_events_source_table_check;
ALTER TABLE alc_api.cam_clip_events ADD CONSTRAINT cam_clip_events_source_table_check
    CHECK (source_table IN ('hub_measurements', 'vein_enroll_events', 'measurements', 'measurements_bp', 'tenko_identity_events'));
