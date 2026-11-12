-- 点呼の事業者 (会社) と受委託、事業者ごとの点呼の届出の値 (足すだけ。Refs ippoan/alc-app#676)
--
-- 1 つのテナントに複数の事業者 (グループの会社) が入り、営業所を事業者に振り分ける。点呼の届出 (書き込む値・申請済みの控え) は
-- 事業者ごとに持ち、事業者間遠隔点呼の受委託 (営業所の組・許可・期間) を登録する。
-- 読み書きは alc-tenko-worker (`/api/tenko/companies`・`/api/tenko/consignments`・`/api/tenko/filing-settings`、admin だけ)。
-- 点呼の判定 (alc-measurements-worker) はまだこの表を読まない (受委託の許可が通ってから切り替える)。
--
-- 1. tenko_companies: 事業者。name は正式名称。is_self はテナントの既定の事業者 (1 テナント 1 行まで)。
--    会社の表が無かったときの営業所 (company_id が NULL) は is_self の事業者とみなす
-- 2. tenko_offices.company_id: 営業所の事業者。既存の company_name (自由記述) からは埋めない (管理画面で振り分ける)。
--    事業者を消すと営業所の事業者は外れる (営業所は残る)。company_name は残す (消すのは後の contract)
-- 3. tenko_consignments: 受委託 1 件 = 委託 (車両の営業所) → 受託 (運行管理者の営業所) の向き。双方向は 2 行。
--    対象は遠隔点呼の業務前・業務後に固定なので列にしない。
--    arrive_id は受委託の許可申請の到達番号 (e-Gov)。許可番号・許可日・期間は結果が出てから入れる (それまで NULL = 申請中)。
--    期間は両方入れるか両方空で、最長 5 年。2 つの営業所の事業者が違うこと (= 営業所も違う) は worker が検める
--    (事業者は別の表なので CHECK で書けない)
-- 4. tenko_company_filing_settings: 点呼の届出の書き込む値を事業者ごとに 1 行 (列は 201・213 の tenko_filing_settings と同じ)。
--    テナントに 1 行の tenko_filing_settings は読まなくなる。今ある行は新しい事業者へ移さずに消す (オーナーの判断。
--    事業者を登録してから値を入れ直す)。表を消すのは後の contract
-- 5. tenko_filing_archive_companies: 申請済みの控え (R2 の `{tenant}/{到達番号}.zip`) をどの事業者に見せるか。
--    受委託の許可申請は委託者・受託者の両方の事業者に付けられるよう、多対多にする
--
-- 外部キーは (tenant_id, <列>) の複合にする (172)。GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

-- 1. tenko_companies
CREATE TABLE alc_api.tenko_companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (btrim(name) <> ''),
    is_self BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenko_companies_tenant_id_id_key UNIQUE (tenant_id, id),
    CONSTRAINT tenko_companies_tenant_id_name_key UNIQUE (tenant_id, name)
);
CREATE UNIQUE INDEX tenko_companies_one_self ON alc_api.tenko_companies (tenant_id) WHERE is_self;

ALTER TABLE alc_api.tenko_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_companies FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_companies_tenant ON alc_api.tenko_companies
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_companies TO alc_api_app;

-- 2. tenko_offices.company_id
ALTER TABLE alc_api.tenko_offices ADD COLUMN company_id UUID NULL;
ALTER TABLE alc_api.tenko_offices ADD CONSTRAINT tenko_offices_company_id_fkey
    FOREIGN KEY (tenant_id, company_id) REFERENCES alc_api.tenko_companies (tenant_id, id) ON DELETE SET NULL (company_id);
CREATE INDEX idx_tenko_offices_company ON alc_api.tenko_offices (tenant_id, company_id);

-- 3. tenko_consignments
CREATE TABLE alc_api.tenko_consignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    consignor_office_id UUID NOT NULL,
    consignee_office_id UUID NOT NULL,
    arrive_id TEXT NULL CHECK (arrive_id ~ '^[0-9]{15,17}[0-9a-z]$'),
    permit_no TEXT NULL CHECK (btrim(permit_no) <> ''),
    permit_date DATE NULL,
    valid_from DATE NULL,
    valid_to DATE NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenko_consignments_tenant_id_id_key UNIQUE (tenant_id, id),
    CONSTRAINT tenko_consignments_period CHECK (
        (valid_from IS NULL) = (valid_to IS NULL)
        AND (valid_to IS NULL OR (valid_to >= valid_from AND valid_to < valid_from + INTERVAL '5 years'))
    ),
    CONSTRAINT tenko_consignments_consignor_office_id_fkey FOREIGN KEY (tenant_id, consignor_office_id)
        REFERENCES alc_api.tenko_offices (tenant_id, id) ON DELETE CASCADE,
    CONSTRAINT tenko_consignments_consignee_office_id_fkey FOREIGN KEY (tenant_id, consignee_office_id)
        REFERENCES alc_api.tenko_offices (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_tenko_consignments_consignor ON alc_api.tenko_consignments (tenant_id, consignor_office_id);
CREATE INDEX idx_tenko_consignments_consignee ON alc_api.tenko_consignments (tenant_id, consignee_office_id);

ALTER TABLE alc_api.tenko_consignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_consignments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_consignments_tenant ON alc_api.tenko_consignments
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_consignments TO alc_api_app;

-- 4. tenko_company_filing_settings (列・既定値・CHECK は tenko_filing_settings から写す)
CREATE TABLE alc_api.tenko_company_filing_settings (
    LIKE alc_api.tenko_filing_settings INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    company_id UUID NOT NULL,
    PRIMARY KEY (tenant_id, company_id),
    CONSTRAINT tenko_company_filing_settings_tenant_id_fkey FOREIGN KEY (tenant_id)
        REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    CONSTRAINT tenko_company_filing_settings_company_id_fkey FOREIGN KEY (tenant_id, company_id)
        REFERENCES alc_api.tenko_companies (tenant_id, id) ON DELETE CASCADE
);

ALTER TABLE alc_api.tenko_company_filing_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_company_filing_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_company_filing_settings_tenant ON alc_api.tenko_company_filing_settings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_company_filing_settings TO alc_api_app;

-- 5. tenko_filing_archive_companies
CREATE TABLE alc_api.tenko_filing_archive_companies (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    arrive_id TEXT NOT NULL CHECK (arrive_id ~ '^[0-9]{15,17}[0-9a-z]$'),
    company_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, arrive_id, company_id),
    CONSTRAINT tenko_filing_archive_companies_company_id_fkey FOREIGN KEY (tenant_id, company_id)
        REFERENCES alc_api.tenko_companies (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX idx_tenko_filing_archive_companies_company
    ON alc_api.tenko_filing_archive_companies (tenant_id, company_id);

ALTER TABLE alc_api.tenko_filing_archive_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_filing_archive_companies FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_filing_archive_companies_tenant ON alc_api.tenko_filing_archive_companies
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_filing_archive_companies TO alc_api_app;

-- 6. 旧い「書き込む値」(テナントに 1 行) を消す。表は FORCE RLS で、本番は表の所有者が流すのでポリシーが掛かり、
--    テナントを設定しない文には行が見えない。この transaction の中だけ FORCE を外して消し、戻す
ALTER TABLE alc_api.tenko_filing_settings NO FORCE ROW LEVEL SECURITY;
DELETE FROM alc_api.tenko_filing_settings;
ALTER TABLE alc_api.tenko_filing_settings FORCE ROW LEVEL SECURITY;
