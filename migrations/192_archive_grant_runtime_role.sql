-- dtakologs の archive (R2 への退避と 7 日超の削除) を alc-dtako-worker の定時実行へ移すための権限。
--
-- 084 の archive_* 関数 5 本は rust-alc-api の archive Job (alc_api_app) から呼ばれていた。
-- worker は共有の Hyperdrive (実行用ロール alc_api_rt) で繋ぐので、alc_api_rt に EXECUTE を明示で付ける。
-- 158 の `GRANT EXECUTE ON ALL FUNCTIONS` と PUBLIC の EXECUTE (検査 7 の許可リスト) で既に呼べるが、
-- それは「その時点で在った関数」と PUBLIC 経由に頼った結果で、worker が呼ぶことを宣言したものではない。
-- PUBLIC からの REVOKE はここではしない (検査 7 の許可リストを外すのは別の migration で扱う)。
--
-- 影響: alc_api_rt で繋ぐ全 worker から、全テナントの dtakologs を読み・消し・書き戻せる関数が呼べる
-- (関数は SECURITY DEFINER で中で archive_mode を立てる)。呼ぶのは alc-dtako-worker の定時実行と
-- 内部の restore の口だけにする。
GRANT EXECUTE ON FUNCTION alc_api.archive_list_dtako_dates() TO alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_fetch_dtako_rows_json(TEXT, TEXT, BIGINT, BIGINT) TO alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_list_old_dtako_dates(TEXT) TO alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_delete_dtako_date(TEXT, TEXT) TO alc_api_rt;
GRANT EXECUTE ON FUNCTION alc_api.archive_upsert_dtako_batch(JSONB) TO alc_api_rt;
