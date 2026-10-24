-- 測定の記録を機体の鍵の ID (`alarm:<fingerprint>`) で残すための列 (足すだけ)
-- Refs ippoan/alc-cam#2
--
-- 1. hub_measurements.via_device_id: CoreS3 が接続に使った hub の credential の device_id。
--    cf-alc-recorder が、hub の JWT と機体の鍵の証明が 1 回の接続で揃ったときだけ書く
--    (device_id には鍵の sub `alarm:<fingerprint>` が入る)。鍵 ⇔ hub の結び付きはこの列から導く
--    (人が対応表を入れない)。来なければ NULL (古い recorder・ブラウザ打刻・過去の行)。
-- 2. measurements.device_id: 測定を作った端末の token の sub (auth-worker が付ける X-Device-Id)。
--    PC 経由の測定 (Vein Station・血圧測定台・CoreS3 の PC) を、録画の自動切り出しで端末から引くため。
--    管理者のログインや無認証の経路で作った行は NULL。
-- 3. cam_clip_events.source_table に measurements (アルコール) と measurements_bp (血圧) を足す。
--    1 行の測定がアルコールと血圧の 2 イベントになるので、unique (tenant, camera, source_table, source_id)
--    に当たらないよう source_table を分ける。制約は作り直し (contract の検査の対象外)。
--
-- 過去の行は書き換えない。

ALTER TABLE alc_api.hub_measurements ADD COLUMN via_device_id TEXT;

-- 結び付きを引く (SELECT DISTINCT via_device_id, device_id ... WHERE via_device_id IS NOT NULL)
CREATE INDEX hub_measurements_tenant_via_device
    ON alc_api.hub_measurements (tenant_id, via_device_id)
    WHERE via_device_id IS NOT NULL;

ALTER TABLE alc_api.measurements ADD COLUMN device_id TEXT;

-- 端末ごとの測定を時刻で引く (録画の自動切り出し・端末候補)
CREATE INDEX measurements_tenant_device_measured_at
    ON alc_api.measurements (tenant_id, device_id, measured_at DESC)
    WHERE device_id IS NOT NULL;

ALTER TABLE alc_api.cam_clip_events DROP CONSTRAINT cam_clip_events_source_table_check;
ALTER TABLE alc_api.cam_clip_events ADD CONSTRAINT cam_clip_events_source_table_check
    CHECK (source_table IN ('hub_measurements', 'vein_enroll_events', 'measurements', 'measurements_bp'));
