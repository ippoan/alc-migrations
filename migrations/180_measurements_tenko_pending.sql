-- 測定の完了と点呼の記録の確定を分ける (足すだけ)
-- Refs ippoan/alc-app#436
--
-- 測定は結果が出た時点で保存し、点呼の記録 (tenko_records は UPDATE / DELETE 禁止) は
-- 結果カードで方法 (IT点呼 / 終了) が選ばれた時点で確定する。選ばれなければ定時実行が
-- 通常点呼で確定する。完了から確定までの間、記録に要る入力 (tenko_type・carins_cert_no・
-- carins_vehicle_id・identity_method) を measurements.tenko_pending に置き、確定したら NULL に戻す。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (理由は 154 の冒頭)。SET LOCAL なので、この migration の中だけに効く。
SET LOCAL lock_timeout = '10s';

-- 1. 確定待ちの入力。NULL = 確定待ちではない (既存の行はすべて NULL)。
ALTER TABLE alc_api.measurements ADD COLUMN tenko_pending JSONB NULL;

-- 定時実行が毎回引くので、確定待ちの行だけの部分 index を張る (確定待ちは常に少数)。
CREATE INDEX idx_measurements_tenko_pending
    ON alc_api.measurements (updated_at)
    WHERE tenko_pending IS NOT NULL;

-- 2. 確定待ちの一覧 (alc-measurements-worker の定時実行用)。
--
-- 定時実行は tenant ヘッダの無い状態で確定待ちの測定を引き、tenant ごとの transaction (RLS) の
-- 中で確定する。実行用ロール alc_api_rt は非所有者なので、measurements を tenant をまたいで読むには
-- SECURITY DEFINER の関数が要る (164 と同じ形)。measurements は FORCE を付けていないので、
-- 所有者として動く DEFINER からは RLS を通って読める。
-- 完了の時刻は updated_at (011。完了の PUT が更新する)。
-- 返すのは定時実行に要る 3 列だけ (tenko_pending の中身や個人の情報は返さない)。
-- 158 の形: SECURITY DEFINER + search_path 固定、動的 SQL なし、PUBLIC から REVOKE。
CREATE FUNCTION alc_api.list_pending_tenko(older_than interval)
RETURNS TABLE (tenant_id uuid, measurement_id uuid, is_dev boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT m.tenant_id, m.id, m.is_dev
      FROM alc_api.measurements m
     WHERE m.tenko_pending IS NOT NULL
       AND m.status = 'completed'
       AND m.updated_at <= now() - older_than
     ORDER BY m.tenant_id, m.updated_at;
$$;
REVOKE ALL ON FUNCTION alc_api.list_pending_tenko(interval) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_pending_tenko(interval) TO alc_api_app, alc_api_rt;
