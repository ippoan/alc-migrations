-- IT点呼 の運行管理者の判定待ちを持つテナントを引く関数 (足すだけ。Refs ippoan/alc-app-s3#352)
--
-- IT点呼 は、端末で測定・保存した後に運行管理者が判定 (manager_judgment) を付けて完了する。判定が付かないまま
-- 何日も残ることがあったため、定時 (毎朝) に判定待ちの一覧を notify のグループ「点呼の異常」へメールで知らせる
-- (alc-tenko-worker の定時実行)。定時のバッチはテナントを横断して引く口が要る。
--
-- list_it_tenko_pending_tenants() は、判定待ちの IT点呼 を持つテナントの tenant_id だけを重複なしで返す。
-- 点呼の中身は返さない (中身はテナントの transaction の中で RLS 越しに読む)。判定待ちの条件は管理画面の一覧
-- (GET /tenko/sessions?tenko_method=IT点呼&judgment_pending=true) と同じ: 点呼方法が IT点呼 で判定が空
-- (status は問わない)。dev端末の行 (is_dev) は数えない。
CREATE FUNCTION alc_api.list_it_tenko_pending_tenants()
RETURNS SETOF UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT DISTINCT s.tenant_id
      FROM alc_api.tenko_sessions s
     WHERE s.tenko_method = 'IT点呼'
       AND s.manager_judgment IS NULL
       AND s.is_dev = FALSE;
$$;
REVOKE ALL ON FUNCTION alc_api.list_it_tenko_pending_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_it_tenko_pending_tenants() TO alc_api_app, alc_api_rt;
