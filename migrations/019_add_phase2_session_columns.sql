-- Phase 2: セッションに自己申告・安全判定・日常点検カラムを追加

-- 自己申告 (要件8): {illness, fatigue, sleep_deprivation, declared_at}
ALTER TABLE tenko_sessions ADD COLUMN IF NOT EXISTS self_declaration JSONB;

-- 安全運転判定 (要件9): {status, failed_items, judged_at, medical_diffs}
ALTER TABLE tenko_sessions ADD COLUMN IF NOT EXISTS safety_judgment JSONB;

-- 日常点検 (要件11): {brakes, tires, lights, steering, wipers, mirrors, horn, seatbelts, inspected_at}
ALTER TABLE tenko_sessions ADD COLUMN IF NOT EXISTS daily_inspection JSONB;
