-- 中間点呼ドライバー (電話番号で識別)
CREATE TABLE IF NOT EXISTS tenko_call_drivers (
    id SERIAL PRIMARY KEY,
    phone_number TEXT NOT NULL UNIQUE,
    driver_name TEXT NOT NULL,
    call_number TEXT,  -- 発信先電話番号 (管理者がWebで設定)
    tenant_id TEXT NOT NULL DEFAULT 'default',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 中間点呼位置情報ログ
CREATE TABLE IF NOT EXISTS tenko_call_logs (
    id SERIAL PRIMARY KEY,
    driver_id INT NOT NULL REFERENCES tenko_call_drivers(id),
    phone_number TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- alc_api_app ロールに権限付与 (RLS なし: 認証不要の public route)
GRANT SELECT, INSERT, UPDATE, DELETE ON tenko_call_drivers TO alc_api_app;
GRANT SELECT, INSERT ON tenko_call_logs TO alc_api_app;
GRANT USAGE, SELECT ON SEQUENCE tenko_call_drivers_id_seq TO alc_api_app;
GRANT USAGE, SELECT ON SEQUENCE tenko_call_logs_id_seq TO alc_api_app;
