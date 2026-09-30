-- 顔認証の実施有無を明示的に記録
-- NULL = 旧データ, true = 認証済み, false = スキップ
ALTER TABLE measurements ADD COLUMN face_verified BOOLEAN;
