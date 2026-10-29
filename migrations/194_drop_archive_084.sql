-- 084 の dtakologs の archive 用の関数 5 本とポリシー 4 本を消す (contract。Refs ippoan/rust-alc-api#680)。
--
-- どちらも rust-alc-api の archive Job (alc_api_app) 専用だった。Job と rust-alc-api は撤収し、dtakologs の退避は
-- alc-dtako-worker の定時実行がテナントごとの transaction (通常の tenant_isolation) で行う。使い手はもう無い。
-- 192 で宛先を alc_api_app に絞った (archive_mode を立てれば全テナントの行が通る形は残っていた) ものを、ここで消す。
-- archive_mode の GUC を読むのはこのポリシーと関数だけなので、ほかに消すものは無い。
DROP POLICY archive_select ON alc_api.dtakologs;
DROP POLICY archive_insert ON alc_api.dtakologs;
DROP POLICY archive_update ON alc_api.dtakologs;
DROP POLICY archive_delete ON alc_api.dtakologs;

DROP FUNCTION alc_api.archive_list_dtako_dates();
DROP FUNCTION alc_api.archive_fetch_dtako_rows_json(TEXT, TEXT, BIGINT, BIGINT);
DROP FUNCTION alc_api.archive_list_old_dtako_dates(TEXT);
DROP FUNCTION alc_api.archive_delete_dtako_date(TEXT, TEXT);
DROP FUNCTION alc_api.archive_upsert_dtako_batch(JSONB);
