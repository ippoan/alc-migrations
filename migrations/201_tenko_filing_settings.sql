-- 点呼の届出・自動点呼機器の認定申請に差し込む値の表 (足すだけ)
--
-- 遠隔点呼・自動点呼の届出 (e-Gov の参考様式・国交省の別紙7 など) と、自動点呼機器の認定申請 (様式1・様式2) の
-- 様式に、管理画面 (alc-app) が値を差し込んでダウンロードさせる。その値をテナントに 1 行で持つ。
-- 読み書きは alc-tenko-worker (`/api/tenko/filing-settings`、admin だけ)。
--
-- * business_number: 事業者番号 (許可書の 12 桁)。business_type: 事業種別 (参考様式 #12 の 1〜8)
-- * offices: 点呼に係る営業所・車庫の配列。要素は {name, address, role} (role は #17 の 1 実施 / 2 被実施 / 3 両方)。
--   様式の申請 1 件目・2 件目… の順に並べるので、順序を持つ配列にする。要素の形は worker が検める
-- * device_name: 使用する機器の名称。auto_cert_pre / auto_cert_post: 業務前・業務後の自動点呼機器の認定番号
-- * operator_*: 届け出る事業者 (別紙7 の住所・氏名又は名称・代表者・連絡先)
-- * applicant_*・product_url: 自動点呼機器の認定申請者 (様式1) と、様式2 に載せる製品ページの URL
--
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。
CREATE TABLE alc_api.tenko_filing_settings (
    tenant_id UUID PRIMARY KEY REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    business_number TEXT NULL CHECK (business_number ~ '^[0-9]{12}$'),
    trade_name TEXT NULL,
    business_type SMALLINT NULL CHECK (business_type BETWEEN 1 AND 8),
    offices JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(offices) = 'array'),
    device_name TEXT NOT NULL DEFAULT '一歩庵点呼 v1',
    auto_cert_pre TEXT NULL,
    auto_cert_post TEXT NULL,
    operator_name TEXT NULL,
    operator_address TEXT NULL,
    operator_representative TEXT NULL,
    operator_contact_name TEXT NULL,
    operator_contact_phone TEXT NULL,
    operator_contact_email TEXT NULL,
    applicant_name TEXT NULL,
    applicant_kana TEXT NULL,
    applicant_address TEXT NULL,
    applicant_contact_name TEXT NULL,
    applicant_contact_dept TEXT NULL,
    applicant_contact_phone TEXT NULL,
    applicant_contact_email TEXT NULL,
    product_url TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE alc_api.tenko_filing_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_filing_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_filing_settings_tenant ON alc_api.tenko_filing_settings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_filing_settings TO alc_api_app;
