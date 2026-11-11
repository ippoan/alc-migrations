-- 点呼の予定超過を、webhook の設定が無いテナントからも引く (足すだけ。Refs ippoan/alc-app#676)
--
-- 自動点呼機器の認定要件 (予定の時刻を過ぎても完了しない点呼を運行管理者へ通知) に合わせ、
-- webhook を設定していない事業者にもメールで知らせる。定期のバッチは今まで
-- list_tenko_overdue_webhook_configs() (migration 158) でしかテナントを横断して引けず、
-- webhook を設定したテナントしか見えなかった。
--
-- list_tenko_overdue_tenants() は、未通知 (overdue_notified_at IS NULL) で超過した予定を持つテナントの
-- tenant_id だけを重複なしで返す。予定の中身は返さない (中身はテナントの transaction の中で RLS 越しに読む)。
-- 超過の条件は、定期のバッチの印付け (alc-tenko-worker の overdue.rs の sql::IS_OVERDUE と sql::CLAIM) の写し:
-- 予定の時刻 + テナントの分数 (tenko_settings.overdue_minutes、行が無ければ 60) を過ぎ、
-- 未消費か、消費したセッションの status が completed・cancelled 以外。webhook の設定の有無は見ない。
CREATE FUNCTION alc_api.list_tenko_overdue_tenants()
RETURNS SETOF UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = alc_api AS $$
    SELECT DISTINCT s.tenant_id
      FROM alc_api.tenko_schedules s
     WHERE s.overdue_notified_at IS NULL
       AND s.scheduled_at + make_interval(mins => COALESCE(
             (SELECT t.overdue_minutes FROM alc_api.tenko_settings t WHERE t.tenant_id = s.tenant_id), 60)) < NOW()
       AND (s.consumed = FALSE OR COALESCE(
             (SELECT ss.status FROM alc_api.tenko_sessions ss
               WHERE ss.id = s.consumed_by_session_id AND ss.tenant_id = s.tenant_id)
             NOT IN ('completed', 'cancelled'), FALSE));
$$;
REVOKE ALL ON FUNCTION alc_api.list_tenko_overdue_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.list_tenko_overdue_tenants() TO alc_api_app, alc_api_rt;
