-- 点呼用電話番号マスタ (組織と紐付け)
CREATE TABLE IF NOT EXISTS tenko_call_numbers (
    id SERIAL PRIMARY KEY,
    call_number TEXT NOT NULL UNIQUE,
    tenant_id TEXT NOT NULL DEFAULT 'default',
    label TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON tenko_call_numbers TO alc_api_app;
GRANT USAGE, SELECT ON SEQUENCE tenko_call_numbers_id_seq TO alc_api_app;
