//! alc-api の DB migration を埋め込んだ薄い crate。
//! `alc_migrations::MIGRATOR.run(&pool).await` で空の DB に 0 から適用できる。

/// 全 migration (sqlx)。SQL 本文は 1 バイトも変えずに埋め込んでいる。
pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

/// テスト用 DB 専用: スキーマ・ロールの初期化 SQL (本番では使わない)。
pub const INIT_LOCAL_DB: &str = include_str!("../scripts/init_local_db.sql");

/// テスト用 DB 専用: migration 適用後にアプリロールへ権限を付与する SQL (本番では使わない)。
pub const LOCAL_APP_GRANTS: &str = include_str!("../scripts/local_app_grants.sql");

/// RLS の不変条件の検査 (1 文の SELECT。違反を 1 行ずつ返し、0 行なら合格)。何も変更しないので本番でも流せる。
pub const RLS_INVARIANTS_QUERY: &str = include_str!("../ci/check_rls_invariants.sql");

/// RLS の不変条件の検査の題の一覧 (検査の番号, 題)。[`RLS_INVARIANTS_QUERY`] が返す `check_no` と同じ番号で、
/// 違反が 0 件のときも「どの検査を流したか」を返すための材料。検査を足す・番号を変えるときはここも直す。
pub const RLS_INVARIANT_CHECKS: &[(i32, &str)] = &[
    (0, "実行用ロール alc_api_rt が在る"),
    (
        1,
        "RLS 有効の表で、alc_api_rt が所有者の資格を取れるなら FORCE ROW LEVEL SECURITY が付いている",
    ),
    (2, "RLS 有効の表が、alc_api_rt に効くポリシーを 1 本以上持つ"),
    (
        3,
        "RLS が無効の表は、許可リスト (tenants / _sqlx_migrations / vehicle_settings_dumps) に在るものだけ",
    ),
    (4, "alc_api_rt が superuser でも BYPASSRLS でもない"),
    (
        5,
        "alc_api_rt が schema の USAGE、全表 (_sqlx_migrations を除く) の SELECT / INSERT / UPDATE / DELETE、全 sequence の USAGE、SECURITY DEFINER の全関数の EXECUTE を持つ",
    ),
];

/// RLS まわりのいまの状態 (1 文の SELECT。`alc_api` schema のカタログを読み、1 行 1 列の JSON `state` を返す)。合否は決めない。何も変更しないので本番でも流せる。
pub const RLS_STATE_QUERY: &str = include_str!("../ci/rls_state.sql");
