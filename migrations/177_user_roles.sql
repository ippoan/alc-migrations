-- ユーザーごとに付け外しできる「ロール」を持つ表 (user_id × role)。
-- alc_api.users.role (admin/viewer/payroll の 1 人 1 値。131 の CHECK) は変えず、それとは別に追加のロールを複数持てる。
-- ロール → 権限の対応はアプリ側 (alc-auth-worker) のコードに固定し、この表は「どのユーザーにどのロールが付いているか」だけを持つ。
-- 最初のロールは leave (休暇申請。権限 leave.use)。ロールを増やすときは CHECK を作り直す migration を足す
-- (Refs ohishi-exp/rust-leave-worker#1)。行は付ける = INSERT、外す = DELETE で使うので UPDATE は付けない。
--
-- FK は leave_periods (168) と同じ単独 FK。users に UNIQUE (tenant_id, id) を足す ALTER はしないため、
-- 親の tenant 一致は 170・176 と同じく WITH CHECK で塞ぐ (ci/check_rls_parent_tenant.sql が行で確かめる)。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。
CREATE TABLE alc_api.user_roles (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES alc_api.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('leave')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, user_id, role)
);

ALTER TABLE alc_api.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.user_roles FORCE ROW LEVEL SECURITY;
CREATE POLICY user_roles_tenant ON alc_api.user_roles
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND EXISTS (
            SELECT 1 FROM alc_api.users u
            WHERE u.id = user_roles.user_id AND u.tenant_id = user_roles.tenant_id
        )
    );
GRANT SELECT, INSERT, DELETE ON alc_api.user_roles TO alc_api_app;
