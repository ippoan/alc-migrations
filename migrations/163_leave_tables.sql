-- 勤怠申請 (有給・労災) 管理の表 5 つと、メールの宛先から tenant を引く関数 1 本。
-- 休暇申請書 PDF の 1 ページ = 申請書 1 枚を、乗務員と期間 (複数行) に手で紐づけ、
-- 一番星の休暇入力と突き合わせて警告するための土台 (Refs ohishi-exp/rust-leave-worker#1)。
-- 乗務員は一番星の 社員C (employee_cd) を文字列で持つ。employees (id) とは結ばない。
--
-- ポリシーは 053 の型 (NULLIF で未設定を NULL にする) で、USING と WITH CHECK の両方に書く。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

-- 1. tenant ごとの設定 (1 行)
--    ENABLE のみで FORCE は付けない: leave_resolve_mailbox (SECURITY DEFINER) が所有者として
--    tenant をまたいで mailbox を引くため (158 の規範「FORCE の付いた表には DEFINER で触らない」)。
--    実行用ロール alc_api_rt は非所有者なので RLS は効く。
CREATE TABLE alc_api.leave_settings (
    tenant_id UUID PRIMARY KEY REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    mailbox TEXT UNIQUE CHECK (mailbox ~ '^[a-z0-9-]{3,64}$'),
    allowed_senders TEXT[] NOT NULL DEFAULT '{}',
    dept_codes TEXT[] NOT NULL DEFAULT '{}',
    lineworks_channel_id UUID REFERENCES alc_api.lineworks_channels(id) ON DELETE SET NULL,
    grace_days INT NOT NULL DEFAULT 7 CHECK (grace_days BETWEEN 0 AND 60),
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE alc_api.leave_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY leave_settings_tenant ON alc_api.leave_settings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.leave_settings TO alc_api_app;

-- 2. PDF 1 ページ = 申請書 1 枚
CREATE TABLE alc_api.leave_pages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    r2_key TEXT NOT NULL,
    page_no INT NOT NULL CHECK (page_no >= 1),
    mail_from TEXT,
    subject TEXT,
    received_at TIMESTAMPTZ NOT NULL,
    employee_cd TEXT,
    status TEXT NOT NULL DEFAULT 'unlinked' CHECK (status IN ('unlinked', 'linked', 'ignored')),
    linked_by TEXT,
    linked_at TIMESTAMPTZ,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (r2_key, page_no)
);
CREATE INDEX leave_pages_tenant_status_idx ON alc_api.leave_pages (tenant_id, status);
CREATE INDEX leave_pages_tenant_employee_idx ON alc_api.leave_pages (tenant_id, employee_cd);

ALTER TABLE alc_api.leave_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.leave_pages FORCE ROW LEVEL SECURITY;
CREATE POLICY leave_pages_tenant ON alc_api.leave_pages
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.leave_pages TO alc_api_app;

-- 3. 1 ページに複数行の期間
CREATE TABLE alc_api.leave_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES alc_api.leave_pages(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('yukyu', 'rousai', 'tokukyu', 'kekkin')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    half TEXT CHECK (half IN ('am', 'pm')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (end_date >= start_date),
    CHECK (half IS NULL OR start_date = end_date)
);
CREATE INDEX leave_periods_tenant_dates_idx ON alc_api.leave_periods (tenant_id, start_date, end_date);

ALTER TABLE alc_api.leave_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.leave_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY leave_periods_tenant ON alc_api.leave_periods
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.leave_periods TO alc_api_app;

-- 4. 有給付与の台帳
CREATE TABLE alc_api.leave_grants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    employee_cd TEXT NOT NULL,
    grant_date DATE NOT NULL,
    days NUMERIC(4,1) NOT NULL CHECK (days >= 0),
    expires_on DATE NOT NULL CHECK (expires_on > grant_date),
    source TEXT NOT NULL CHECK (source IN ('auto', 'manual')),
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, employee_cd, grant_date)
);

ALTER TABLE alc_api.leave_grants ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.leave_grants FORCE ROW LEVEL SECURITY;
CREATE POLICY leave_grants_tenant ON alc_api.leave_grants
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.leave_grants TO alc_api_app;

-- 5. 突合の警告 (二重送信を防ぐ)
CREATE TABLE alc_api.leave_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    employee_cd TEXT NOT NULL,
    day DATE NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('yukyu', 'rousai', 'tokukyu', 'kekkin')),
    direction TEXT NOT NULL CHECK (direction IN ('ichiban_only', 'pdf_only')),
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notified_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    UNIQUE (tenant_id, employee_cd, day, kind, direction)
);

ALTER TABLE alc_api.leave_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.leave_alerts FORCE ROW LEVEL SECURITY;
CREATE POLICY leave_alerts_tenant ON alc_api.leave_alerts
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.leave_alerts TO alc_api_app;

-- 6. メールの宛先 (local-part) から tenant と許可する差出人を引く。受信時は tenant が未確定。
--    158 の形: SECURITY DEFINER + search_path 固定、動的 SQL なし、PUBLIC から REVOKE。
--    leave_settings は FORCE を付けていないので、所有者として動けば RLS を通る。
CREATE FUNCTION alc_api.leave_resolve_mailbox(p_mailbox TEXT)
RETURNS TABLE (tenant_id UUID, allowed_senders TEXT[])
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT s.tenant_id, s.allowed_senders
      FROM alc_api.leave_settings s
     WHERE s.mailbox = lower(p_mailbox) AND s.enabled;
$$;
REVOKE ALL ON FUNCTION alc_api.leave_resolve_mailbox(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.leave_resolve_mailbox(TEXT) TO alc_api_app, alc_api_rt;
