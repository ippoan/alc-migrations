-- dtakologs の archive (R2 への退避と 7 日超の削除) の権限を、rust-alc-api の archive Job (alc_api_app) だけに絞る。
--
-- 084 の archive_* 関数 5 本と、archive_mode で全テナントの行を通す 4 本のポリシー (archive_select / insert /
-- update / delete) は、rust-alc-api の archive Job のためのもの。退避は alc-dtako-worker の定時実行へ移し、
-- worker はテナントごとの transaction (通常の tenant_isolation) で dtakologs を読み消しするので、どちらも使わない。
--
-- 1. 084 のポリシーは条件が `current_setting('alc_api.archive_mode', true) = 'true'` だけで宛先が PUBLIC だった。
--    実行用ロール alc_api_rt で繋ぐ worker が `set_config('alc_api.archive_mode', 'true', true)` を打てば、
--    全テナントの dtakologs が見え、消せた。宛先を alc_api_app に限る (式は変えない)。
-- 2. archive_* 5 本の EXECUTE を PUBLIC と alc_api_rt から外す (084 で alc_api_app に付けた分は残す。
--    alc_api_rt の分は 158 の `GRANT EXECUTE ON ALL FUNCTIONS`)。
--
-- 本番の archive Job は alc_api_app で繋ぐ (関数は所有者の資格で動く) ので、どちらもいまの Job を壊さない。
-- 関数とポリシーを消す (contract) のは、Job を止めた後の別の migration。
ALTER POLICY archive_select ON alc_api.dtakologs TO alc_api_app;
ALTER POLICY archive_insert ON alc_api.dtakologs TO alc_api_app;
ALTER POLICY archive_update ON alc_api.dtakologs TO alc_api_app;
ALTER POLICY archive_delete ON alc_api.dtakologs TO alc_api_app;

REVOKE ALL ON FUNCTION alc_api.archive_list_dtako_dates() FROM PUBLIC, alc_api_rt;
REVOKE ALL ON FUNCTION alc_api.archive_fetch_dtako_rows_json(TEXT, TEXT, BIGINT, BIGINT) FROM PUBLIC, alc_api_rt;
REVOKE ALL ON FUNCTION alc_api.archive_list_old_dtako_dates(TEXT) FROM PUBLIC, alc_api_rt;
REVOKE ALL ON FUNCTION alc_api.archive_delete_dtako_date(TEXT, TEXT) FROM PUBLIC, alc_api_rt;
REVOKE ALL ON FUNCTION alc_api.archive_upsert_dtako_batch(JSONB) FROM PUBLIC, alc_api_rt;
