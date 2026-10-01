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

バイナリ (`cli` feature):

```bash
DATABASE_URL=postgresql://... cargo run --features cli --bin alc-migrate
```

## 取り込みの手順
1. migration を足し、`Cargo.toml` の版を migration 番号に合わせて PR → merge
2. rust-alc-api の `Cargo.toml` で、この crate の `rev` を merge 後の main のコミットの SHA に上げる

tag は使わない。crates.io には出さない (`Cargo.toml` は `publish = false`)。

## License
MIT
