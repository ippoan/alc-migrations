-- tenko_sessions.schedule_id の FK を ON DELETE SET NULL に変更
-- セッションが紐づいているスケジュールを削除可能にする
ALTER TABLE tenko_sessions
    DROP CONSTRAINT tenko_sessions_schedule_id_fkey;

ALTER TABLE tenko_sessions
    ADD CONSTRAINT tenko_sessions_schedule_id_fkey
    FOREIGN KEY (schedule_id) REFERENCES tenko_schedules(id)
    ON DELETE SET NULL;
