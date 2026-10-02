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

## 配り方
rust-alc-api が git 依存 (rev 固定) で読む。取り込みは rust-alc-api の `Cargo.toml` の rev を上げる。
tag は打たない。crates.io には出さない (`publish = false`)。

## public repo の注意
ホスト名・ID・本番データを migration・コメント・コミットに書かない。

## 検証
`cargo fmt --check && cargo clippy --all-features -- -D warnings && cargo test`。
DB を使う確認は CI の `replay` job (init → alc-migrate → grants → `_sqlx_migrations` の件数 → `ci/*.sql` の検査)。
migration を足したら `ci.yml` の件数の期待値 (`<件数> | <最大番号>`。133 が欠番なので件数 = 最大番号 − 1) も更新する。
検査用の SQL は `ci/` に置く (`scripts/*.sql` は crate に含まれるので置かない)。
`ci/` のうち crate に入るのは `check_rls_invariants.sql` だけ (backend が同じ 1 文を流すため。`alc_migrations::RLS_INVARIANTS_QUERY`)。ほかの検査 SQL は今までどおり入れない。
`check_rls_invariants.sql` は 1 文の SELECT のまま保つ (文を足さない・psql のメタコマンドを使わない)。
