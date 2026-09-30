-- tenko_sessions: remoteMode 対応のため schedule_id と responsible_manager_name を nullable に変更
ALTER TABLE tenko_sessions ALTER COLUMN schedule_id DROP NOT NULL;
ALTER TABLE tenko_sessions ALTER COLUMN responsible_manager_name DROP NOT NULL;
