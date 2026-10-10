#!/usr/bin/env bash
# テナントを持つ表どうしの外部キーが tenant_id を含む複合になっているかの gate (CI の replay job)。
# ci/check_fk_tenant_composite.sql の出力 (複合になっていない外部キー) を、許可リスト
# ci/fk_tenant_composite_allowlist.txt の先頭 4 項目 (子の表 | 列 | 親の表 | 制約名) と比べる。落とすのは 2 つ:
#   * 検査に出たのに許可リストに無い外部キー (新しく作った非複合の外部キー)
#   * 許可リストに在るのに検査に出ない行 (複合に直した・消した外部キー。許可リストから消させる)
# 違いを stdout に 1 行ずつ出して exit 1。一致なら exit 0。
#
# 接続は PG* の環境変数。1 transaction で流して ROLLBACK する (検査は SELECT だけで何も変えない)。
# 引数を渡すと、検査の前に同じ transaction の中で流す (CI の対照が使い捨ての表を作る / 外部キーを消すため):
#   bash ci/check_fk_tenant_composite.sh ['<SQL>']
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
allowlist="$dir/fk_tenant_composite_allowlist.txt"

args=(-v ON_ERROR_STOP=1 -q -At -F ' | ' -c BEGIN)
if [ $# -gt 0 ]; then
  args+=(-c "$1")
fi
args+=(-f "$dir/check_fk_tenant_composite.sql" -c ROLLBACK)
found=$(psql "${args[@]}")

allowed=$(grep -v -e '^#' -e '^[[:space:]]*$' "$allowlist" | cut -d '|' -f 1-4 | sed 's/ $//')

unexpected=$(comm -23 <(printf '%s\n' "$found" | sed '/^$/d' | LC_ALL=C sort) <(printf '%s\n' "$allowed" | LC_ALL=C sort))
stale=$(comm -13 <(printf '%s\n' "$found" | sed '/^$/d' | LC_ALL=C sort) <(printf '%s\n' "$allowed" | LC_ALL=C sort))

status=0
if [ -n "$unexpected" ]; then
  printf '%s\n' "$unexpected" | sed 's/^/not-composite | /'
  status=1
fi
if [ -n "$stale" ]; then
  printf '%s\n' "$stale" | sed 's/^/stale-allowlist | /'
  status=1
fi
if [ "$status" -eq 0 ]; then
  echo "ok: 複合になっていない外部キー $(printf '%s\n' "$found" | sed '/^$/d' | wc -l) 本 = 許可リスト"
fi
exit "$status"
