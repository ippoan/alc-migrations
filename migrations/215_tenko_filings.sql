-- 点呼の届出 (遠隔点呼・自動点呼の実施の届出) の申請の下書き (足すだけ。Refs ippoan/alc-app#676)
--
-- 様式を作った時点で申請の下書きを 1 行残し、e-Gov へ出した後に到達番号を付けて状況を追えるようにする。
-- 読み書きは alc-tenko-worker (admin だけ)。
-- 到達番号と事業者の対応の正本は tenko_filing_archive_companies (214)。この表は下書きと到達番号へのリンクだけを持つ。
--
-- tenko_filings: 申請 1 件 = 事業者 1 つの届出 1 通。
--   kind は remote (遠隔点呼) / auto (自動点呼)。
--   offices は作成時点の営業所の写し (配列。要素は {office_id, role (1 実施 / 2 被実施 / 3 両方), name, address})。
--   営業所マスタが後で変わっても出した内容が残るよう、外部キーにしない。要素の形の検査は worker がする。
--   arrive_id は e-Gov の到達番号で、提出後に付ける (それまで NULL = 下書き)。形の検査は worker がする
--   (控えの到達番号と同じ検査)。同じテナントの中で 1 つの到達番号は 1 件の申請にだけ付く。
--   created_by / created_by_name は作った人 (利用者を消しても行は残すので外部キーにしない)。
--
-- 外部キーは (tenant_id, <列>) の複合にする (172)。GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

CREATE TABLE alc_api.tenko_filings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('remote', 'auto')),
    apply_date DATE NOT NULL,
    start_date DATE NULL,
    offices JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(offices) = 'array'),
    arrive_id TEXT NULL,
    created_by UUID NULL,
    created_by_name TEXT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenko_filings_tenant_id_id_key UNIQUE (tenant_id, id),
    CONSTRAINT tenko_filings_company_id_fkey FOREIGN KEY (tenant_id, company_id)
        REFERENCES alc_api.tenko_companies (tenant_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX tenko_filings_tenant_arrive_id_key
    ON alc_api.tenko_filings (tenant_id, arrive_id) WHERE arrive_id IS NOT NULL;
CREATE INDEX idx_tenko_filings_company
    ON alc_api.tenko_filings (tenant_id, company_id, created_at DESC);

ALTER TABLE alc_api.tenko_filings ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.tenko_filings FORCE ROW LEVEL SECURITY;
CREATE POLICY tenko_filings_tenant ON alc_api.tenko_filings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_filings TO alc_api_app;
