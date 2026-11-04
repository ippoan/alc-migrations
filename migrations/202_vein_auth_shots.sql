-- 指静脈の認証のたびの撮影と状態、サーバーでの判定の結果 (足すだけ。Refs ippoan/alc-app-s3#352)
--
-- 本番の判定はモジュールのまま。認証のたびに端末 (alc-app) がその場の撮影と認証の状態を送り、
-- alc-vein-worker が撮影を vein-match の chara_verify にかけて結果を残す。閾値や計算を直したら、
-- 残した撮影で判定し直す (判定の表に行を足す。前の判定は消さない)。送るのは検証用のテナントだけ
-- (auth-worker が絞る)。撮影は生体データなので worker が暗号化してから書く (ここは暗号文だけを持つ)。
-- 撮影は 90 日で消す (worker の定時実行が vein_auth_shots_purge を呼ぶ。判定は CASCADE で消える)。
--
-- GRANT ON ALL TABLES は既存表のスナップショットなので新表に効かない (忘れると本番で 502)。
-- alc_api_rt へは 158 の ALTER DEFAULT PRIVILEGES で付くので書かない。

-- 1. 認証 1 回 = 1 行
--    ENABLE のみで FORCE は付けない: vein_auth_shots_purge (SECURITY DEFINER) が所有者として
--    テナントをまたいで古い行を消すため (163 の leave_settings と同じ。158 の規範「FORCE の付いた表には
--    DEFINER で触らない」)。実行用ロール alc_api_rt は非所有者なので RLS は効く。
CREATE TABLE alc_api.vein_auth_shots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    -- 免許証で決まった乗務員 (照合の前に決まっている本人)
    employee_id UUID NOT NULL,
    -- 撮った端末 (端末の token の sub。vein_device_records.device_id と同じもの)
    device_id TEXT NOT NULL,
    -- 端末のファームの版 (端末が名乗った文字列。分からなければ NULL)
    firmware TEXT NULL,
    -- モジュールの判定: 当たった (IDENTIFIED) / 当たらない (NOMATCH)
    module_result TEXT NOT NULL CHECK (module_result IN ('IDENTIFIED', 'NOMATCH')),
    -- 当たったモジュールの枠 (NOMATCH は NULL)
    module_slot INT NULL,
    -- 枠の持ち主: 本人 (self) / 他人 (other) / 不一致 (none)
    module_hit TEXT NOT NULL CHECK (module_hit IN ('self', 'other', 'none')),
    -- モジュールの点数 (SCORE=) と閾値 (THS=)。古いファームは出さないので NULL
    module_score INT NULL,
    module_thresholds INT[] NULL,
    -- 端末がそのとき記録をどう組んで取っていたか (own = その端末の記録だけ / NULL = 混ぜた記録)。
    -- 判定し直しで本人の記録を同じ組み方で組むため
    pick TEXT NULL CHECK (pick IN ('own')),
    -- 撮影の形: ファームの 1 本撮りの記録 (record) / 0xbdbd の特徴量 (chara)
    shot_kind TEXT NOT NULL CHECK (shot_kind IN ('record', 'chara')),
    -- 撮影 (base64) を worker が暗号化したもの。復号の鍵は DB に無い
    shot_encrypted TEXT NOT NULL,
    -- 端末で照合した時刻
    captured_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT vein_auth_shots_tenant_id_key UNIQUE (tenant_id, id),
    CONSTRAINT vein_auth_shots_employee_id_fkey FOREIGN KEY (tenant_id, employee_id)
        REFERENCES alc_api.employees (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX vein_auth_shots_tenant_created_idx ON alc_api.vein_auth_shots (tenant_id, created_at);

ALTER TABLE alc_api.vein_auth_shots ENABLE ROW LEVEL SECURITY;
CREATE POLICY vein_auth_shots_tenant ON alc_api.vein_auth_shots
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.vein_auth_shots TO alc_api_app;

-- 2. 判定 1 回 = 1 行 (受けたときに 1 回、判定し直すたびに 1 回)
CREATE TABLE alc_api.vein_auth_judgments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    shot_id UUID NOT NULL,
    -- 判定した計算の版 (vein-match の版と閾値。worker が組む文字列)
    logic_version TEXT NOT NULL,
    -- 判定の形: 本人の記録と 1:1 (self) / 粗い比較の上位 10 人を chara_verify (top10)
    method TEXT NOT NULL CHECK (method IN ('self', 'top10')),
    -- 1 人だけ通った (match) / 2 人以上通った (again) / 誰も通らない (nomatch) / 判定できない (error)
    result TEXT NOT NULL CHECK (result IN ('match', 'again', 'nomatch', 'error')),
    -- match のときの乗務員
    matched_employee_id UUID NULL,
    -- 試した相手ごとの結果 [{employee_id, matched, scores}] (相手の記録そのものは持たない)
    candidates JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(candidates) = 'array'),
    -- 判定できなかった理由 (error のとき)
    error TEXT NULL,
    -- 判定にかかった時間 (マイクロ秒)
    elapsed_us INT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT vein_auth_judgments_shot_id_fkey FOREIGN KEY (tenant_id, shot_id)
        REFERENCES alc_api.vein_auth_shots (tenant_id, id) ON DELETE CASCADE
);
CREATE INDEX vein_auth_judgments_shot_idx ON alc_api.vein_auth_judgments (tenant_id, shot_id, created_at);

ALTER TABLE alc_api.vein_auth_judgments ENABLE ROW LEVEL SECURITY;
ALTER TABLE alc_api.vein_auth_judgments FORCE ROW LEVEL SECURITY;
CREATE POLICY vein_auth_judgments_tenant ON alc_api.vein_auth_judgments
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.vein_auth_judgments TO alc_api_app;

-- 3. 90 日より古い撮影を消す (alc-vein-worker の定時実行。テナントの指定なし)
--    164 の形: SECURITY DEFINER + search_path 固定、動的 SQL なし、PUBLIC から REVOKE。
--    消した行数を返す。判定の行は外部キーの CASCADE で消える。
CREATE FUNCTION alc_api.vein_auth_shots_purge()
RETURNS BIGINT
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    WITH gone AS (
        DELETE FROM alc_api.vein_auth_shots
         WHERE created_at < now() - interval '90 days'
        RETURNING 1
    )
    SELECT count(*) FROM gone;
$$;
REVOKE ALL ON FUNCTION alc_api.vein_auth_shots_purge() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.vein_auth_shots_purge() TO alc_api_app, alc_api_rt;
