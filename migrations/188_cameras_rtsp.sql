-- 拠点 PC の配信 (alc-cam の拡張 + host) が RTSP で繋ぐ先を DB に持つ (足すだけ)
-- Refs ippoan/alc-cam#2
--
-- 拠点 PC の手入力をやめ、担当の端末 (cam_camera_devices) にだけ接続先と資格情報を返す (alc-cam ingest の GET /cameras/mine)。
-- 資格情報は録画用の rec_username / rec_password_encrypted (187) を使い回すので、ここでは足さない。
--
-- 1. lan_ip: 拠点の LAN から見たカメラの IP。113 の ip (ONVIF の死活監視。backend の PUT /api/cameras が書き換える) とも、
--    187 の rec_ip (中身は VPC Service の binding 名) とも別の列にする。NULL = RTSP の設定なし。
-- 2. rtsp_port: 既定 554。NOT NULL DEFAULT の定数なので既存行の書き換えは起きず、backend の INSERT も壊さない。
-- 3. rtsp_path: RTSP の URL のパス (先頭の / なし。例 stream1)。NULL = RTSP の設定なし。
--
-- 権限は表単位 (113 の alc_api_app、158 の alc_api_rt) なので、足した列にもそのまま効く。列単位の GRANT は無い。

ALTER TABLE alc_api.cameras
    ADD COLUMN lan_ip TEXT NULL,
    ADD COLUMN rtsp_port INTEGER NOT NULL DEFAULT 554,
    ADD COLUMN rtsp_path TEXT NULL,
    ADD CONSTRAINT cameras_rtsp_port_check CHECK (rtsp_port BETWEEN 1 AND 65535);
