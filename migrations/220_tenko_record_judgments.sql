-- 点呼の記録に紐づく、運行管理者の判定の追記 (足すだけ。Refs ippoan/alc-app#723, #722, #676)
--
-- 自己点検表 業務前 二十 タ「運行管理者が、運転者が運行の業務に従事することができないと判断した場合の理由及び
-- 代替措置の内容」と、要件 22「記録は変えられない、または最初と最新が残る」のため。
--
-- アルコール検知・日常点検 NG で自動で中止した点呼は、その時点で記録 (tenko_records) を書いて閉じる。記録は
-- trigger で UPDATE・DELETE を拒むので、後から運行管理者が入れた判定と代替措置は記録に入らなかった。
-- また CSV の判定の列は点呼 (tenko_sessions) の列から読んでいて、何度でも上書きでき履歴が無かった。
--
-- tenko_record_judgments: 判定 1 回 = 1 行。記録 1 件に何行でも足せ、最新の行がその記録の判定になる。
-- 書き換え・削除は tenko_records と同じく trigger で拒む (追記だけ)。
--   judgment は ok (従事できる) / ng (従事できない)。ng のときは理由と代替措置が必須 (空白だけも不可)。
--   judged_by は判定した運行管理者 (社員)。judged_by_name はその時点の氏名の写し (後で社員が変わっても残す)。
--   method は確認の方法 (157 の manager_judgment_method と同じ値。無ければ NULL)。
--
-- tenko_records と同じく is_dev の軸を持つ (153)。既定値は接続の app.device_dev から決まる。
-- 外部キーは (tenant_id, <列>) の複合にする (172)。そのため tenko_records に UNIQUE (tenant_id, id) を足す
-- (index を作るだけで行の UPDATE にはならないので、記録の trigger には当たらない)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.tenko_records ADD CONSTRAINT tenko_records_tenant_id_id_key UNIQUE (tenant_id, id);

CREATE TABLE alc_api.tenko_record_judgments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    record_id UUID NOT NULL,
    judgment TEXT NOT NULL CHECK (judgment IN ('ok', 'ng')),
    reason TEXT NULL,
    alternative_measure TEXT NULL,
    method TEXT NULL CHECK (method IN ('it', 'in_person')),
    judged_by UUID NOT NULL,
    judged_by_name TEXT NOT NULL,
    is_dev BOOLEAN NOT NULL DEFAULT (coalesce(current_setting('app.device_dev', true), '') = '1'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT tenko_record_judgments_record_id_fkey FOREIGN KEY (tenant_id, record_id)
        REFERENCES alc_api.tenko_records (tenant_id, id),
    CONSTRAINT tenko_record_judgments_judged_by_fkey FOREIGN KEY (tenant_id, judged_by)
        REFERENCES alc_api.employees (tenant_id, id),
    -- 従事できない (ng) と判断したときは理由と代替措置がそろう (業務前 二十 タ)
    CONSTRAINT tenko_record_judgments_ng_check CHECK (
        judgment <> 'ng'
        OR (reason IS NOT NULL AND btrim(reason) <> ''
            AND alternative_measure IS NOT NULL AND btrim(alternative_measure) <> '')
    )
);
CREATE INDEX idx_tenko_record_judgments_record
    ON alc_api.tenko_record_judgments (tenant_id, record_id, created_at DESC);

ALTER TABLE alc_api.tenko_record_judgments ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation_tenko_record_judgments ON alc_api.tenko_record_judgments
    USING (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    )
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id')::UUID
        AND is_dev = (coalesce(current_setting('app.device_dev', true), '') = '1')
    );
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.tenko_record_judgments TO alc_api_app;

-- 改ざん防止: 追記だけ (UPDATE / DELETE を拒む)
CREATE FUNCTION alc_api.prevent_tenko_record_judgment_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = alc_api
AS $$
BEGIN
    RAISE EXCEPTION 'tenko_record_judgments cannot be modified or deleted (tamper prevention)';
END;
$$;

CREATE TRIGGER trg_prevent_tenko_record_judgment_update
    BEFORE UPDATE ON alc_api.tenko_record_judgments
    FOR EACH ROW
    EXECUTE FUNCTION alc_api.prevent_tenko_record_judgment_modification();

CREATE TRIGGER trg_prevent_tenko_record_judgment_delete
    BEFORE DELETE ON alc_api.tenko_record_judgments
    FOR EACH ROW
    EXECUTE FUNCTION alc_api.prevent_tenko_record_judgment_modification();
