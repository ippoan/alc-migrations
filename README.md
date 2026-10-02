# alc-migrations

alc-api の DB migration (SQL) を埋め込んだ薄い crate。migration だけを monolith から分け、CI を速く回すための repo。
SQL は rust-alc-api の `03e0571` から 1 バイトも変えずに移してある (sqlx の checksum は SQL 本文だけで決まるため、本番の `_sqlx_migrations` とそのまま一致する)。

## 版の規約
`0.<最新の migration 番号>.<patch>`。migration を足したら minor を上げ、SQL 以外の変更は patch を上げる。

## 使い方

git 依存で読む (rev 固定)。crates.io には出していない。

```toml
[dev-dependencies]
alc-migrations = { git = "https://github.com/ippoan/alc-migrations", rev = "<コミットの SHA>" }
```

```rust
alc_migrations::MIGRATOR.run(&pool).await?;
```

テスト用 DB 向けに `alc_migrations::INIT_LOCAL_DB` / `LOCAL_APP_GRANTS` (init / grants の SQL) も公開している。本番では使わない。

`alc_migrations::RLS_INVARIANTS_QUERY` は RLS の不変条件の検査 (`ci/check_rls_invariants.sql` そのもの。1 文の SELECT で、0 行なら合格)。何も変更しないので本番でも流せる。

バイナリ (`cli` feature):

```bash
DATABASE_URL=postgresql://... cargo run --features cli --bin alc-migrate
```

## 取り込みの手順
1. migration を足し、`Cargo.toml` の版を migration 番号に合わせて PR → merge
2. rust-alc-api の `Cargo.toml` で、この crate の `rev` を merge 後の main のコミットの SHA に上げる

tag は使わない。crates.io には出さない (`Cargo.toml` は `publish = false`)。

## ロールと RLS (migration 158〜)

本番では、migration を流すロール `alc_api_app` が `alc_api` の全表の所有者で、backend は所有者でない実行用ロール `alc_api_rt` で繋ぐ。
PostgreSQL は `FORCE ROW LEVEL SECURITY` の無い表では所有者にポリシーを適用しないので、RLS が掛かるのは `alc_api_rt` の接続だけ。
migration 118〜120・137 のコメントの「`alc_api_app` は非所有者」は誤り (適用済みの migration は直せないので、ここに記す)。

migration を書くときの決まり:

- 新しい表は RLS を有効にする。RLS 無しの表を足すなら、`ci/check_rls_invariants.sql` の許可リストに足し、理由をそこのコメントに書く
- ポリシーに `TO <role>` を書かない (宛先は PUBLIC)。書くなら `alc_api_rt` を含める。含めないと backend からは 1 行も見えない
- `alc_api_rt` への表・sequence・関数の権限は、158 の `ALTER DEFAULT PRIVILEGES` で自動で付く。migration に `GRANT … TO alc_api_rt` を書かなくてよい (`GRANT … TO alc_api_app` は今までどおり書く。CI の `postgres` の軸では `alc_api_app` が所有者でないため)
- 関数を PUBLIC から `REVOKE` したら、`alc_api_rt` に `GRANT EXECUTE` を明示する (`REVOKE … FROM PUBLIC` は `alc_api_rt` の EXECUTE を消さないが、誰が呼べるかを読んで分かるようにする)
- migration の中の DML は所有者として動くので、RLS の影響を受けない。ただし FORCE 付きの表は受ける (tenant context を立てないと 0 行・拒否になる)
- `SECURITY DEFINER` 関数も所有者として動く。FORCE 付きの表に触る関数は、中で tenant context を立てる

CI の replay job は「migration を流すロール」の 2 つの軸で回る:

| 軸 | 表の所有者 | RLS を確かめるロール | 見つけるもの |
|---|---|---|---|
| `postgres` | `postgres` | `alc_api_app` | migration の GRANT 漏れ (所有者には GRANT が要らないので、もう片方の軸では見つからない) |
| `alc_api_app` | `alc_api_app` (本番と同じ) | `alc_api_rt` | superuser でないと通らない文、所有者だから素通りしている RLS |

どちらの軸でも `ci/check_rls_invariants.sql` を流し、「ポリシーを書いたが backend に効いていない」を落とす
(所有者の資格を取れる / 効くポリシーが無い / RLS 無しの表が増えた / 権限が付いていない)。
この SQL は 1 文の SELECT (違反を 1 行ずつ返す。0 行なら合格) で、何も変更しないので本番でもそのまま流せる。
CI は同じファイルを実行用ロール (`SET ROLE alc_api_rt`) でも流し、違反を作ったときに行が出ること (陽性対照) も確かめる。

## License
MIT
