-- 顔特徴量 (128-dim float64 配列) をサーバー側に保存
ALTER TABLE employees ADD COLUMN IF NOT EXISTS face_embedding FLOAT8[];
ALTER TABLE employees ADD COLUMN IF NOT EXISTS face_embedding_at TIMESTAMPTZ;
