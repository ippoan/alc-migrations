-- 休暇申請の PDF のページ (leave_pages) と、一番星 (販売管理) の運転日報明細の行 (休暇の行) を結ぶ表。
-- 紐づけたページごとに「どの行か (row_id)」と、そのときの中身 (乗務員C・日・品名・最終更新) を持つ。
-- 毎朝一番星と比べ、行が消えた・最終更新や中身が変わったら紐づけを解除するのは rust-leave-worker 側で行う
-- (Refs ohishi-exp/rust-leave-worker#1)。行は全消し→入れ直しで使うので UPDATE は付けない。
--
-- row_id は一番星の 管理年月日(YYYYMMDD)-管理C。行が編集されても変わらない。
-- last_updated は一番星の 最終更新 を CONVERT(varchar(23), ..., 121) で文字にしたもの (NULL あり)。
-- item_name は一番星の 品名N の正規化前の生の値。
--
-- FK は leave_periods (168) と同じ単独 FK。leave_pages に UNIQUE (tenant_id, id) が無く親表は ALTER しないため、
-- 親の tenant 一致は 170 と同じく WITH CHECK で塞ぐ (ci/check_rls_parent_tenant.sql が行で確かめる)。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。
CREATE TABLE alc_api.leave_link_rows (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES alc_api.leave_pages(id) ON DELETE CASCADE,
    row_id TEXT NOT NULL,
    employee_cd TEXT NOT NULL,
    day DATE NOT NULL,
    item_name TEXT NOT NULL,
    last_updated TEXT NULL,
    PRIMARY KEY (page_id, row_id)
);

CREATE INDEX leave_link_rows_tenant_day ON alc_api.leave_link_rows (tenant_id, day);

ALTER TABLE alc_api.leave_link_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.leave_link_rows FORCE ROW LEVEL SECURITY;
CREATE POLICY leave_link_rows_tenant ON alc_api.leave_link_rows
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND EXISTS (
            SELECT 1 FROM alc_api.leave_pages p
            WHERE p.id = leave_link_rows.page_id AND p.tenant_id = leave_link_rows.tenant_id
        )
    );
GRANT SELECT, INSERT, DELETE ON alc_api.leave_link_rows TO alc_api_app;
