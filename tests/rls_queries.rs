use alc_migrations::{
    RLS_EXPECTED_STATE, RLS_INVARIANTS_QUERY, RLS_INVARIANT_CHECKS, RLS_STATE_QUERY,
};
use std::collections::BTreeSet;

/// 検査 SQL の `violation` CTE の各枝の先頭 (`SELECT <番号>, '`) から番号を取る。
fn check_numbers_in_query() -> Vec<i32> {
    RLS_INVARIANTS_QUERY
        .lines()
        .filter_map(|line| {
            let rest = line.trim_start().strip_prefix("SELECT ")?;
            let (no, _) = rest.split_once(", '")?;
            no.parse().ok()
        })
        .collect()
}

/// コメント行を除いた SQL の本文。
fn sql_body(sql: &str) -> String {
    sql.lines()
        .filter(|line| !line.trim_start().starts_with("--"))
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn invariant_checks_match_the_branches_of_the_query() {
    let branches = check_numbers_in_query();
    // 現行は 14 本の枝 (検査 5 が 4 本、検査 7 が 2 本)。枝を足したら、ここと RLS_INVARIANT_CHECKS を見直す。
    assert_eq!(branches.len(), 14, "violation CTE の枝の数: {branches:?}");

    let in_query: BTreeSet<i32> = branches.into_iter().collect();
    let in_list: BTreeSet<i32> = RLS_INVARIANT_CHECKS.iter().map(|(no, _)| *no).collect();
    assert_eq!(in_query, in_list);
    assert_eq!(in_list, (0..=9).collect::<BTreeSet<i32>>());
}

#[test]
fn invariant_checks_are_ascending_without_duplicates_and_titled() {
    let numbers: Vec<i32> = RLS_INVARIANT_CHECKS.iter().map(|(no, _)| *no).collect();
    assert!(numbers.windows(2).all(|w| w[0] < w[1]), "{numbers:?}");
    assert!(RLS_INVARIANT_CHECKS
        .iter()
        .all(|(_, title)| !title.trim().is_empty()));
}

/// driver の prepared statement で流せる形: 文は 1 つ、引数・psql のメタコマンド・ブロックコメントなし。
#[test]
fn state_query_is_a_single_read_only_statement() {
    let body = sql_body(RLS_STATE_QUERY);
    assert_eq!(body.matches(';').count(), 1);
    assert!(body.trim_end().ends_with(';'));
    assert!(body.trim_start().starts_with("WITH "));
    assert!(body.contains(") AS state;"));
    assert!(!body.contains('$'));
    assert!(!body.contains("/*"));
    assert!(body
        .lines()
        .all(|line| !line.trim_start().starts_with('\\')));
    for word in [
        "SET ROLE",
        "INSERT INTO",
        "UPDATE ",
        "DELETE FROM",
        "pg_stat_activity",
        "current_setting",
    ] {
        assert!(!body.contains(word), "{word}");
    }
}

/// 2 回流して同じ出力になるよう、状態の SQL の jsonb_agg / array_agg は全部 ORDER BY を持つ。
#[test]
fn state_query_orders_every_aggregate() {
    let body = sql_body(RLS_STATE_QUERY);
    let aggregates = body.matches("jsonb_agg(").count() + body.matches("array_agg(").count();
    assert!(aggregates > 0);
    // 集約の開き括弧から次の集約 (または末尾) までの間に ORDER BY が在ること
    for (start, _) in body.match_indices("_agg(") {
        let rest = &body[start + "_agg(".len()..];
        let end = rest.find("_agg(").unwrap_or(rest.len());
        assert!(
            rest[..end].contains("ORDER BY"),
            "ORDER BY の無い集約: {}",
            &rest[..end.min(80)]
        );
    }
}

/// 期待する状態は `jq -S` で整形した JSON の object (依存を足さないので、形は文字列で見る)。
/// 最上位に policy_names / tables / table_count が在り、環境で違う `owner` は入っていない。
#[test]
fn expected_state_is_normalized_json_without_owner() {
    assert!(RLS_EXPECTED_STATE.starts_with("{\n"));
    assert!(RLS_EXPECTED_STATE.ends_with("\n}\n"));
    // 字下げ 2 の行 = 最上位の key
    let top_level: Vec<&str> = RLS_EXPECTED_STATE
        .lines()
        .filter(|line| line.starts_with("  \""))
        .filter_map(|line| line[3..].split_once("\": ").map(|(key, _)| key))
        .collect();
    for key in ["policy_names", "table_count", "tables"] {
        assert!(top_level.contains(&key), "{key}: {top_level:?}");
    }
    assert!(top_level.windows(2).all(|w| w[0] < w[1]), "{top_level:?}");
    assert!(!RLS_EXPECTED_STATE.contains("\"owner\""));
}
