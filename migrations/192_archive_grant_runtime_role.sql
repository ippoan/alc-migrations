-- dtakologs の archive (R2 への退避と 7 日超の削除) を alc-dtako-worker の定時実行へ移すための権限の整理。
--
-- 084 の archive_* 関数 5 本は PUBLIC から REVOKE されておらず (PostgreSQL は新しい関数の EXECUTE を既定で
-- PUBLIC に付ける)、検査 7 の許可リストに載っていた。worker は共有の Hyperdrive (実行用ロール alc_api_rt) で繋ぐので、
-- ほかの SECURITY DEFINER の関数 (158 の形) と同じく PUBLIC から REVOKE し、alc_api_app と alc_api_rt にだけ付ける
-- (alc_api_rt は 158 の `GRANT EXECUTE ON ALL FUNCTIONS` で既に持っているが、ここで明示する)。
--
-- 影響: alc_api_rt で繋ぐ全 worker から、全テナントの dtakologs を読み・消し・書き戻せる関数が呼べる
-- (関数は SECURITY DEFINER で中で archive_mode を立てる)。呼ぶのは alc-dtako-worker の定時実行と
-- 内部の restore の口だけにする。同じ DB に居るこのアプリのものでないロールからは呼べなくなる。
REVOKE ALL ON FUNCTION alc_api.archive_list_dtako_dates() FROM PUBLIC;
REVOKE ALL ON FUNCTION alc_api.archive_fetch_dtako_rows_json(TEXT, TEXT, BIGINT, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION alc_api.archive_list_old_dtako_dates(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION alc_api.archive_delete_dtako_date(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION alc_api.archive_upsert_dtako_batch(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION alc_api.archive_list_dtako_dates() TO alc_api_app, alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_fetch_dtako_rows_json(TEXT, TEXT, BIGINT, BIGINT) TO alc_api_app, alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_list_old_dtako_dates(TEXT) TO alc_api_app, alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_delete_dtako_date(TEXT, TEXT) TO alc_api_app, alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_upsert_dtako_batch(JSONB) TO alc_api_app, alc_api_rt;
