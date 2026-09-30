-- notify_documents: メール受信用カラム追加
-- email_message_id: 同一メールに含まれた複数添付をまとめるグルーピングID
-- source_body_text: メール本文 (プレーンテキスト)
-- source_received_at: メール受信日時 (Email Worker が記録)
ALTER TABLE alc_api.notify_documents
    ADD COLUMN IF NOT EXISTS email_message_id UUID,
    ADD COLUMN IF NOT EXISTS source_body_text TEXT,
    ADD COLUMN IF NOT EXISTS source_received_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_notify_documents_email_message_id
    ON alc_api.notify_documents(tenant_id, email_message_id)
    WHERE email_message_id IS NOT NULL;

-- notify_deliveries: 「だれが送信を実行したか」を記録
-- NULL は古い行 (この機能導入前のレコード) または自動配信
ALTER TABLE alc_api.notify_deliveries
    ADD COLUMN IF NOT EXISTS triggered_by_user_id UUID REFERENCES alc_api.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_notify_deliveries_triggered_by
    ON alc_api.notify_deliveries(tenant_id, triggered_by_user_id)
    WHERE triggered_by_user_id IS NOT NULL;
