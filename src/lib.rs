//! alc-api の DB migration を埋め込んだ薄い crate。
//! `alc_migrations::MIGRATOR.run(&pool).await` で空の DB に 0 から適用できる。

/// 全 migration (sqlx)。SQL 本文は 1 バイトも変えずに埋め込んでいる。
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

/// テスト用 DB 専用: スキーマ・ロールの初期化 SQL (本番では使わない)。
pub const INIT_LOCAL_DB: &str = include_str!("../scripts/init_local_db.sql");

/// テスト用 DB 専用: migration 適用後にアプリロールへ権限を付与する SQL (本番では使わない)。
pub const LOCAL_APP_GRANTS: &str = include_str!("../scripts/local_app_grants.sql");
