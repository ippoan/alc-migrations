-- 着信スケジュール・通知ON/OFF をデバイス管理に移動
ALTER TABLE alc_api.devices ADD COLUMN call_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE alc_api.devices ADD COLUMN call_schedule JSONB;
