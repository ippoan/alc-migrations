-- 拠点カメラの SD 録画の自動切り出しの土台の表 (足すだけ)
-- Refs ippoan/alc-cam#2
--
-- アルコール・血圧・IC (timecard/license)・指静脈の登録のイベントの前後 10 秒を、カメラの SD 録画から
-- 切り出して R2 に置く (Worker alc-cam-sd-ingest の cron)。カメラは複数台で、宛先・資格情報を DB に持ち、
-- 映している端末を結び付ける。台帳は新設せず、既存の alc_api.cameras (113、ONVIF の死活監視) を拡張する。
--
-- 1. cameras に録画の取り込み用の列を足す (全部 NULL 可・DEFAULT なし。既存行と backend の INSERT / UPDATE を壊さない)。
--    宛先は既存の ip ではなく新しい列 rec_ip に持つ: backend の PUT /api/cameras が ip を書き換えられるため。
--    rec_ip は backend から書かない。「録画を取り込む」= rec_ip IS NOT NULL。ポートは 80 固定で列を持たない。
-- 2. cam_camera_devices: カメラと、そのカメラが映している端末 (hub_measurements.device_id と同じ文字列) の結び付け。
-- 3. cam_clips: 切り出した MP4 の台帳。カメラを消すと R2 に孤児ができるので RESTRICT。
-- 4. cam_clip_events: クリップに含めたイベント。is_dev 軸付き (179 と同じ)。
-- 5. vein_enroll_events: 指静脈の登録の履歴 (vein_templates は 1 人 1 行の上書きで履歴が無い)。is_dev 軸付き。
-- 6. list_cam_recording_tenant_ids(): 録画を取り込むカメラを持つテナントの id (cron がテナントを巡るため。158 と同じ書き方)。
--
-- FK は 172 の規約どおり tenant を含む複合。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

-- 1. cameras
ALTER TABLE alc_api.cameras
    ADD COLUMN rec_ip TEXT NULL,
    ADD COLUMN rec_username TEXT NULL,
    ADD COLUMN rec_password_encrypted TEXT NULL,
    ADD COLUMN rec_scanned_until TIMESTAMPTZ NULL;

-- 全テナントで同じ宛先は 1 行 (既存行は全部 NULL なので作成は落ちない)
CREATE UNIQUE INDEX cameras_rec_ip_key ON alc_api.cameras (rec_ip) WHERE rec_ip IS NOT NULL;

-- 2. cam_camera_devices
CREATE TABLE alc_api.cam_camera_devices (
    tenant_id UUID NOT NULL,
    camera_id UUID NOT NULL,
    device_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, camera_id, device_id),
    CONSTRAINT cam_camera_devices_camera_id_fkey FOREIGN KEY (tenant_id, camera_id)
        REFERENCES alc_api.cameras (tenant_id, id) ON DELETE CASCADE
);

-- 3. cam_clips
CREATE TABLE alc_api.cam_clips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    camera_id UUID NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    r2_key TEXT NOT NULL,
    size_bytes BIGINT NULL,
    status TEXT NOT NULL CHECK (status IN ('ready', 'failed')),
    error TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT cam_clips_period_check CHECK (ended_at > started_at),
    CONSTRAINT cam_clips_tenant_id_id_key UNIQUE (tenant_id, id),
    CONSTRAINT cam_clips_tenant_camera_started_key UNIQUE (tenant_id, camera_id, started_at),
    CONSTRAINT cam_clips_camera_id_fkey FOREIGN KEY (tenant_id, camera_id)
        REFERENCES alc_api.cameras (tenant_id, id) ON DELETE RESTRICT
);

-- 4. cam_clip_events (source_id の型は hub_measurements.id = UUID に合わせる)
CREATE TABLE alc_api.cam_clip_events (
    tenant_id UUID NOT NULL,
    camera_id UUID NOT NULL,
    clip_id UUID NOT NULL,
    source_table TEXT NOT NULL CHECK (source_table IN ('hub_measurements', 'vein_enroll_events')),
    source_id UUID NOT NULL,
    kind TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    device_id TEXT NULL,
    is_dev BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- 同じイベントを同じカメラで二度切らない (1 イベントが複数カメラに映るのは可)
    CONSTRAINT cam_clip_events_source_key UNIQUE (tenant_id, camera_id, source_table, source_id),
    CONSTRAINT cam_clip_events_clip_id_fkey FOREIGN KEY (tenant_id, clip_id)
        REFERENCES alc_api.cam_clips (tenant_id, id) ON DELETE RESTRICT,
    CONSTRAINT cam_clip_events_camera_id_fkey FOREIGN KEY (tenant_id, camera_id)
        REFERENCES alc_api.cameras (tenant_id, id) ON DELETE RESTRICT
);
ALTER TABLE alc_api.cam_clip_events ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');

-- 5. vein_enroll_events
CREATE TABLE alc_api.vein_enroll_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    employee_id UUID NOT NULL,
    registered_device_id TEXT NULL,
    is_dev BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT vein_enroll_events_tenant_id_id_key UNIQUE (tenant_id, id),
    CONSTRAINT vein_enroll_events_employee_id_fkey FOREIGN KEY (tenant_id, employee_id)
        REFERENCES alc_api.employees (tenant_id, id)
);
ALTER TABLE alc_api.vein_enroll_events ALTER COLUMN is_dev
    SET DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1');
CREATE INDEX vein_enroll_events_tenant_created_idx ON alc_api.vein_enroll_events (tenant_id, created_at);

-- 6. RLS + GRANT
ALTER TABLE alc_api.cam_camera_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.cam_camera_devices FORCE ROW LEVEL SECURITY;
CREATE POLICY cam_camera_devices_tenant ON alc_api.cam_camera_devices
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.cam_camera_devices TO alc_api_app;

ALTER TABLE alc_api.cam_clips ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.cam_clips FORCE ROW LEVEL SECURITY;
CREATE POLICY cam_clips_tenant ON alc_api.cam_clips
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.cam_clips TO alc_api_app;

ALTER TABLE alc_api.cam_clip_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.cam_clip_events FORCE ROW LEVEL SECURITY;
CREATE POLICY cam_clip_events_tenant ON alc_api.cam_clip_events
    USING (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.cam_clip_events TO alc_api_app;

ALTER TABLE alc_api.vein_enroll_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.vein_enroll_events FORCE ROW LEVEL SECURITY;
CREATE POLICY vein_enroll_events_tenant ON alc_api.vein_enroll_events
    USING (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.vein_enroll_events TO alc_api_app;

-- 7. 録画を取り込むカメラを持つテナントの id (158 の list_dev_device_tenant_ids と同じ書き方)
CREATE FUNCTION alc_api.list_cam_recording_tenant_ids()
RETURNS SETOF UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT DISTINCT c.tenant_id
      FROM alc_api.cameras c
     WHERE c.rec_ip IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION alc_api.list_cam_recording_tenant_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_cam_recording_tenant_ids() TO alc_api_app, alc_api_rt;
