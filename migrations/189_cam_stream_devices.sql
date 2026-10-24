-- 拠点カメラの配信担当の端末を順位付きで持つ (足すだけ)
-- Refs ippoan/alc-cam#2
--
-- 同じカメラに鍵が 2 台分紐づくと 2 台とも配信しに行き、cam-room (device は 1 本) の後の 1 台が弾かれ続けた。
-- カメラごとに配信する端末を順位で決め、1 位が居ないときは次の順位が引き継ぐ (cam-room が順位で入れ替える)。
-- cam_camera_devices (187。切り出しと遠隔点呼のカメラ引き) の意味は変えず、配信担当は別の表に持つ。
--
-- cam_stream_devices: カメラと、そのカメラを配信する端末 (拠点 PC の鍵の sub `alarm:<fingerprint>`) と順位。
--   priority は 1 = 主。同じカメラに同じ順位を作らない (UNIQUE)。上限 10。
--   1 つの端末が複数のカメラの順位表に入るのは許す (別のカメラのサブを兼ねる)。
--
-- FK は 172 の規約どおり tenant を含む複合 (カメラを消せば一緒に消える)。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

CREATE TABLE alc_api.cam_stream_devices (
    tenant_id UUID NOT NULL,
    camera_id UUID NOT NULL,
    device_id TEXT NOT NULL,
    priority SMALLINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, camera_id, device_id),
    CONSTRAINT cam_stream_devices_priority_check CHECK (priority BETWEEN 1 AND 10),
    CONSTRAINT cam_stream_devices_priority_key UNIQUE (tenant_id, camera_id, priority),
    CONSTRAINT cam_stream_devices_camera_id_fkey FOREIGN KEY (tenant_id, camera_id)
        REFERENCES alc_api.cameras (tenant_id, id) ON DELETE CASCADE
);

-- 拠点 PC の鍵 (device_id) から担当のカメラを引く (GET /cameras/mine)
CREATE INDEX cam_stream_devices_device_idx ON alc_api.cam_stream_devices (tenant_id, device_id);

ALTER TABLE alc_api.cam_stream_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.cam_stream_devices FORCE ROW LEVEL SECURITY;
CREATE POLICY cam_stream_devices_tenant ON alc_api.cam_stream_devices
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.cam_stream_devices TO alc_api_app;
