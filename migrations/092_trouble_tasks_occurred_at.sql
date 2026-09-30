-- タスクに occurred_at カラム追加 + next_action_by を UUID → TEXT に変更
ALTER TABLE alc_api.trouble_tasks
    ADD COLUMN occurred_at TIMESTAMPTZ,
    ALTER COLUMN next_action_by TYPE TEXT USING next_action_by::text;
