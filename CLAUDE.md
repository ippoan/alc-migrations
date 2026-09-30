# alc-migrations

alc-api の DB migration (sqlx) を埋め込んだ薄い crate。SQL 以外のコードは最小限に保つ。

## migration の規範
- 適用済み migration は絶対に変更しない (checksum で起動不能)。直すときは新しいファイルを足す
- `SECURITY DEFINER` には `SET search_path = alc_api` を付ける
- `WITH CHECK (true)` を避ける
- 既存データへの INSERT / UPDATE をハードコードしない (`WHERE EXISTS`)
- 既定は「足すだけ」(expand)。消す・名前を変える (contract) は、rust-alc-api と全 worker が新スキーマへ移った後に別 PR で出す
- migration を足したら `Cargo.toml` の minor を最新の migration 番号に合わせる (`tests/migrator.rs` の期待値も更新)
- 番号 133 は欠番 (移設元の時点で存在しない)。埋めない
- `migrations/*.sql` は 1 バイトも変えない (末尾改行の追加も不可)。`.gitattributes` の `* -text` を外さない

## 版の規約
`0.<最新の migration 番号>.<patch>`。minor = migration 番号、patch = SQL 以外の変更。

## public repo の注意
ホスト名・ID・本番データを migration・コメント・コミットに書かない。

## 検証
`cargo fmt --check && cargo clippy --all-features -- -D warnings && cargo test`。
DB を使う確認は CI の `replay` job (init → alc-migrate → grants → `_sqlx_migrations` の件数)。
