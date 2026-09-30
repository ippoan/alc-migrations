# alc-migrations

alc-api の DB migration (SQL) を埋め込んだ薄い crate。migration だけを monolith から分け、CI を速く回すための repo。
SQL は rust-alc-api の `03e0571` から 1 バイトも変えずに移してある (sqlx の checksum は SQL 本文だけで決まるため、本番の `_sqlx_migrations` とそのまま一致する)。

## 版の規約
`0.<最新の migration 番号>.<patch>`。migration を足したら minor を上げ、SQL 以外の変更は patch を上げる。

## 使い方

```toml
[dev-dependencies]
alc-migrations = "0.152"
```

```rust
alc_migrations::MIGRATOR.run(&pool).await?;
```

テスト用 DB 向けに `alc_migrations::INIT_LOCAL_DB` / `LOCAL_APP_GRANTS` (init / grants の SQL) も公開している。本番では使わない。

バイナリ (`cli` feature):

```bash
DATABASE_URL=postgresql://... cargo run --features cli --bin alc-migrate
```

## 公開の手順
1. `Cargo.toml` の版を migration 番号に合わせて PR → merge
2. `v<版>` の tag を push (例: `v0.152.0`)
3. `publish.yml` が crates.io の trusted publishing (OIDC) で `cargo publish` する。secret は不要

初回のみ、crates.io で crate を作成し、trusted publishing に本 repo の `publish.yml` を登録しておく。

## License
MIT
