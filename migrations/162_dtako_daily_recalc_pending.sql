-- 日別 (dtako_daily_work_hours / dtako_daily_work_segments) の「要再計算」の印を置く表。
-- デジタコの取り込みで、新しい運行・変わった運行の 乗務員 × 月 にだけ印を付け、
-- 後で印の分だけ日別を計算し直して印を消す (Refs ippoan/alc-dtako-worker#23)。
--
-- month は月初の日 (CHECK で縛る)。印は ON CONFLICT DO NOTHING で付け、計算し直したら DELETE する。
-- UPDATE はしない。alc_api_app へは SELECT / INSERT / DELETE を明示する。
-- alc_api_rt は 158 の default privileges で付く (UPDATE を含む)。
-- driver_id は dtako_daily_work_hours (054) と同じく employees(id) を参照する。
CREATE TABLE alc_api.dtako_daily_recalc_pending (
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    driver_id UUID NOT NULL REFERENCES alc_api.employees(id),
    month DATE NOT NULL CHECK (month = date_trunc('month', month)::date),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, driver_id, month)
);

ALTER TABLE alc_api.dtako_daily_recalc_pending ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.dtako_daily_recalc_pending FORCE ROW LEVEL SECURITY;
CREATE POLICY dtako_daily_recalc_pending_tenant ON alc_api.dtako_daily_recalc_pending
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID);

-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。
GRANT SELECT, INSERT, DELETE ON alc_api.dtako_daily_recalc_pending TO alc_api_app;
