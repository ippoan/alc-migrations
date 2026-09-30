-- status カラム追加（既存レコードは completed）
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'completed';
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- alcohol_level を NULL 許可（Step1 時点では未測定）
ALTER TABLE measurements ALTER COLUMN alcohol_level DROP NOT NULL;

-- result を NULL 許可 + CHECK 制約を再作成
ALTER TABLE measurements ALTER COLUMN result DROP NOT NULL;
ALTER TABLE measurements DROP CONSTRAINT IF EXISTS measurements_result_check;
ALTER TABLE measurements ADD CONSTRAINT measurements_result_check
    CHECK (result IS NULL OR result IN ('pass', 'fail', 'normal', 'over', 'error'));

-- status の CHECK 制約
ALTER TABLE measurements DROP CONSTRAINT IF EXISTS measurements_status_check;
ALTER TABLE measurements ADD CONSTRAINT measurements_status_check
    CHECK (status IN ('started', 'completed'));

-- 未完了レコード検索用インデックス
CREATE INDEX IF NOT EXISTS idx_measurements_status
    ON measurements(tenant_id, status) WHERE status != 'completed';
