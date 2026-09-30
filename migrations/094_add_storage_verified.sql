-- storage_verified: NULL=未確認, true=R2に存在確認済み, false=R2に存在しない
ALTER TABLE files ADD COLUMN IF NOT EXISTS storage_verified BOOLEAN DEFAULT NULL;

-- 既存ファイル: s3_key がある場合は verified=true とみなす（移行済みデータ）
-- s3_key が NULL の場合は blob に格納されているため verified=true
UPDATE files SET storage_verified = true WHERE storage_verified IS NULL;

-- GRANT (alc_api_app ロールに権限付与)
GRANT SELECT, INSERT, UPDATE, DELETE ON files TO alc_api_app;
