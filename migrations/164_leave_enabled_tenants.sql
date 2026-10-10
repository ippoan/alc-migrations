-- 勤怠申請を有効にしている tenant の一覧 (rust-leave-worker の定時実行用)。
--
-- 定時実行は tenant ヘッダの無い状態で「有効な tenant」を引き、tenant ごとに tenant_tx で突合する。
-- 実行用ロール alc_api_rt は非所有者なので、leave_settings を tenant をまたいで読むには
-- leave_resolve_mailbox (163) と同じ形の SECURITY DEFINER 関数が要る。
-- leave_settings は FORCE を付けていないので、所有者として動く DEFINER からは RLS を通って読める。
-- 返すのは定時実行に要る列だけ (mailbox / allowed_senders は返さない)。
-- 158 の形: SECURITY DEFINER + search_path 固定、動的 SQL なし、PUBLIC から REVOKE。
CREATE FUNCTION alc_api.leave_enabled_tenants()
RETURNS TABLE (tenant_id UUID, dept_codes TEXT[], lineworks_channel_id UUID, grace_days INT)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT s.tenant_id, s.dept_codes, s.lineworks_channel_id, s.grace_days
      FROM alc_api.leave_settings s
     WHERE s.enabled
     ORDER BY s.tenant_id;
$$;
REVOKE ALL ON FUNCTION alc_api.leave_enabled_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.leave_enabled_tenants() TO alc_api_app, alc_api_rt;
