-- 運行状況報告の音声録音URL列を追加
ALTER TABLE tenko_sessions
    ADD COLUMN report_vehicle_road_audio_url TEXT,
    ADD COLUMN report_driver_alternation_audio_url TEXT;

ALTER TABLE tenko_records
    ADD COLUMN report_vehicle_road_audio_url TEXT,
    ADD COLUMN report_driver_alternation_audio_url TEXT;
