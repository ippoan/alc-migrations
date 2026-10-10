use alc_migrations::MIGRATOR;

/// 001〜164。133 は欠番 (rust-alc-api 03e0571 の時点で存在しない)。
fn expected_versions() -> Vec<i64> {
    (1..=164).filter(|v| *v != 133).collect()
}

#[test]
fn versions_are_ascending_without_gaps_or_duplicates() {
    let actual: Vec<i64> = MIGRATOR.iter().map(|m| m.version).collect();
    assert_eq!(actual, expected_versions());
}

#[test]
fn latest_version_matches_crate_minor() {
    let max = MIGRATOR.iter().map(|m| m.version).max().unwrap();
    let minor: i64 = env!("CARGO_PKG_VERSION_MINOR").parse().unwrap();
    assert_eq!(max, minor);
}
