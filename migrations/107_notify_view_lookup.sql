-- 配信トークンから既読化せずに閲覧用情報をルックアップする SECURITY DEFINER 関数。
-- nuxt-notify の公開 viewer ページ (/v/{token}) が呼び出す:
--   GET /api/notify/v/{token}      → メタデータ JSON
--   GET /api/notify/v/{token}/file → R2 presigned URL に redirect
-- どちらも既読化はしない (既読は /api/notify/read/{token} で確定)。
CREATE OR REPLACE FUNCTION alc_api.lookup_delivery_for_view(p_read_token UUID)
RETURNS TABLE(
    document_id UUID,
    tenant_id UUID,
    r2_key TEXT,
    file_name TEXT,
    file_size_bytes BIGINT,
    source_subject TEXT,
    source_sender TEXT,
    source_received_at TIMESTAMPTZ,
    expire_at TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api
AS $$
    SELECT d.document_id, d.tenant_id,
           doc.r2_key, doc.file_name, doc.file_size_bytes,
           doc.source_subject, doc.source_sender, doc.source_received_at,
           d.expire_at
    FROM alc_api.notify_deliveries d
    JOIN alc_api.notify_documents doc ON doc.id = d.document_id
    WHERE d.read_token = p_read_token
$$;

GRANT EXECUTE ON FUNCTION alc_api.lookup_delivery_for_view(UUID) TO alc_api_app;
