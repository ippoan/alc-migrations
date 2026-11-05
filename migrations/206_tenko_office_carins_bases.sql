-- 車検証から車両の所属営業所を決める対応表 (足すだけ)
--
-- 205 の点呼の営業所で、車両の所属は基本を車検証 (car_inspection) から決める。車検証の「使用の本拠の位置」と
-- 「使用者の氏名又は名称」の組ごとに、管理画面 (alc-app の「点呼の営業所」) で営業所を 1 回選ぶ。点呼の判定
-- (alc-measurements-worker) は、セッションの車両の車検証からこの組を引いて営業所を決める。
-- 手で選んだ車両の所属 (maintenance_vehicles.office_id、205) は例外の上書きとして優先する。
-- carins が無いテナント・車検証に無い車両は、手の選択だけで動く (この表は空のまま)。
--
-- * use_base: btrim("UseheadqrterChar")
-- * user_name: btrim(COALESCE(NULLIF(btrim("UsernameHighLevelChar"), ''), "UsernameLowLevelChar"))
--   (読み書きする alc-tenko-worker と判定の alc-measurements-worker が同じ式で car_inspection から作る)
-- * 1 組は 1 営業所 (主キー)。営業所を消すと対応も消える
--
-- car_inspection は取り込みで行が差し替わるので、外部キーは張らない (142 と同じ)。
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。alc_api_rt へは 158 の
-- ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

CREATE TABLE alc_api.tenko_office_carins_bases (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    office_id UUID NOT NULL,
    use_base TEXT NOT NULL CHECK (btrim(use_base) <> ''),
    user_name TEXT NOT NULL CHECK (btrim(user_name) <> ''),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, use_base, user_name),
    CONSTRAINT tenko_office_carins_bases_office_id_fkey FOREIGN KEY (tenant_id, office_id)
        REFERENCES alc_api.tenko_offices (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_tenko_office_carins_bases_office
    ON alc_api.tenko_office_carins_bases (tenant_id, office_id);

ALTER TABLE alc_api.tenko_office_carins_bases ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_office_carins_bases FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_office_carins_bases_tenant ON alc_api.tenko_office_carins_bases
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_office_carins_bases TO alc_api_app;
