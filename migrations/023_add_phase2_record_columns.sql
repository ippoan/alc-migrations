-- Phase 2: 不変レコードに新フィールド追加
ALTER TABLE tenko_records ADD COLUMN IF NOT EXISTS self_declaration JSONB;
ALTER TABLE tenko_records ADD COLUMN IF NOT EXISTS safety_judgment JSONB;
ALTER TABLE tenko_records ADD COLUMN IF NOT EXISTS daily_inspection JSONB;
ALTER TABLE tenko_records ADD COLUMN IF NOT EXISTS interrupted_at TIMESTAMPTZ;
ALTER TABLE tenko_records ADD COLUMN IF NOT EXISTS resumed_at TIMESTAMPTZ;
ALTER TABLE tenko_records ADD COLUMN IF NOT EXISTS resume_reason TEXT;
