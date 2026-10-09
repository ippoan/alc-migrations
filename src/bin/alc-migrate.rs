use sqlx::migrate::Migrate;
use sqlx::postgres::PgPoolOptions;
use std::process::ExitCode;

enum Mode {
    Apply,
    Status,
    Check,
}

fn parse_mode() -> Option<Mode> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.as_slice() {
        [] => Some(Mode::Apply),
        [a] if a == "--status" => Some(Mode::Status),
        [a] if a == "--check" => Some(Mode::Check),
        _ => None,
    }
}

// 接続文字列・接続先をログに出さないため、エラーは種類だけを出す
fn kind(e: &sqlx::Error) -> &'static str {
    match e {
        sqlx::Error::Configuration(_) => "configuration",
        sqlx::Error::Database(_) => "database",
        sqlx::Error::Io(_) => "io",
        sqlx::Error::Tls(_) => "tls",
        sqlx::Error::Protocol(_) => "protocol",
        sqlx::Error::PoolTimedOut => "pool timed out",
        sqlx::Error::Migrate(_) => "migrate",
        _ => "other",
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let Some(mode) = parse_mode() else {
        eprintln!("usage: alc-migrate [--status | --check]");
        return ExitCode::from(2);
    };
    let Ok(database_url) = std::env::var("DATABASE_URL") else {
        eprintln!("DATABASE_URL must be set");
        return ExitCode::FAILURE;
    };
    match run(mode, &database_url).await {
        Ok(code) => code,
        Err(e) => {
            eprintln!("error: {}", kind(&e));
            ExitCode::FAILURE
        }
    }
}

async fn run(mode: Mode, database_url: &str) -> Result<ExitCode, sqlx::Error> {
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(database_url)
        .await?;

    if let Mode::Apply = mode {
        alc_migrations::MIGRATOR.run(&pool).await?;
        println!("Migrations completed successfully");
        return Ok(ExitCode::SUCCESS);
    }

    // 何も書かない。台帳の表が無ければ全件未適用 (run と同じ search_path で解決する)
    let has_ledger: bool = sqlx::query_scalar("SELECT to_regclass('_sqlx_migrations') IS NOT NULL")
        .fetch_one(&pool)
        .await?;
    let applied: Vec<i64> = if has_ledger {
        let mut conn = pool.acquire().await?;
        conn.list_applied_migrations()
            .await
            .map_err(sqlx::Error::from)?
            .into_iter()
            .map(|m| m.version)
            .collect()
    } else {
        Vec::new()
    };

    let mut pending = 0usize;
    for m in alc_migrations::MIGRATOR.iter() {
        if m.migration_type.is_down_migration() || applied.contains(&m.version) {
            continue;
        }
        pending += 1;
        println!("{} {}", m.version, m.description);
    }
    println!("pending: {pending}");

    Ok(if matches!(mode, Mode::Check) && pending > 0 {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    })
}
