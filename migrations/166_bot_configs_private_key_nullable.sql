-- LINE WORKS Bot の Private Key を、Cloudflare Secrets Store の 1 本 (alc-lineworks-worker が読む) に一本化する。
-- 先に NOT NULL を外し、rust-alc-api の bot_admin が鍵を受け取らずに行を作れるようにする (expand)。
-- 列の DROP は、全部の読み手が消えた後の別 PR (contract、手動) で行う。既存行は変えない。
-- Refs ippoan/rust-alc-api#747
ALTER TABLE alc_api.bot_configs ALTER COLUMN private_key_encrypted DROP NOT NULL;
