-- Phase A: ingest_key 廃止 + shared secret 化リファクタ
-- Worker ⇄ backend 認証は NOTIFY_WORKER_SECRET (env) 1 個で代替し、
-- テナント特定は body の tenant_slug を tenants.slug で引く方式に切り替えた。
-- 旧 notify_ingest_keys テーブルと verify_ingest_key 関数は不要になる。

DROP FUNCTION IF EXISTS alc_api.verify_ingest_key(TEXT);
DROP TABLE IF EXISTS alc_api.notify_ingest_keys;
