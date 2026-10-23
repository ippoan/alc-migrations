-- 血圧の通知の設定の表 (足すだけ)
-- Refs ippoan/alc-app#436
--
-- 血圧の通知 (測った本人への LINE WORKS、毎朝の管理者への日報メール) の宛先と受け取りの設定を、
-- 既存の通知の宛先 (notify_recipients・通知のグループ) とは別に、1 社員 1 行で持つ。
-- lineworks_user_id・email が NULL の行は、その方法では送らない。
-- notify_self = 測った本人へ LINE WORKS で送るか。daily_report = 日報メールを受け取るか (オプトアウト)。
-- 1 つの LINE WORKS のユーザーは 1 人の社員にだけ結び付ける (部分 UNIQUE)。
--
-- FK は 172 の規約どおり tenant を含む複合。社員を消したら設定も消す。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。
CREATE TABLE alc_api.bp_notify_settings (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL,
    lineworks_user_id TEXT NULL,
    lineworks_name TEXT NULL,
    email TEXT NULL,
    notify_self BOOLEAN NOT NULL DEFAULT TRUE,
    daily_report BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, employee_id),
    CONSTRAINT bp_notify_settings_employee_fkey FOREIGN KEY (tenant_id, employee_id)
        REFERENCES alc_api.employees (tenant_id, id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX idx_bp_notify_settings_lineworks
    ON alc_api.bp_notify_settings (tenant_id, lineworks_user_id)
    WHERE lineworks_user_id IS NOT NULL;

ALTER TABLE alc_api.bp_notify_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.bp_notify_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY bp_notify_settings_tenant ON alc_api.bp_notify_settings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.bp_notify_settings TO alc_api_app;
