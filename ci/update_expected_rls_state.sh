#!/usr/bin/env bash
# ci/expected_rls_state.json (期待する RLS の状態) を作り直す。引数なし。
#
# RLS の状態を変える migration (表・ポリシー・SECURITY DEFINER の関数・sequence・権限) を足したら、
# CI の replay job と同じ手順 (init_local_db.sql → alc-migrate → local_app_grants.sql) で空の DB に
# 全 migration を当て、その DB に PG* の環境変数 (PGHOST / PGPORT / PGUSER / PGPASSWORD / PGDATABASE) で
# 繋いでこれを流す。出来た JSON の差分を、migration と同じ PR に入れる。
#
#   PGHOST=localhost PGUSER=postgres PGPASSWORD=... PGDATABASE=postgres ci/update_expected_rls_state.sh
#
# 中身 = ci/rls_state.sql の出力から各組の owner を取り除き、key を並べて字下げ 2 で整形したもの。
# 正規化の規則はこの 1 つ (jq -S 'del(.tables[].owner)')。CI の比較も、backend の比較も同じ規則を使う。
# owner (所有者のロール名) は環境で違うので外す。出し分けに効く「実行用ロールが所有者の資格を取れるか」は
# runtime_role_can_act_as_owner (真偽) に残る。
#
# ポリシーの式と関数の signature の文字列は、PostgreSQL の版と接続の search_path に依る
# (CI は PostgreSQL 17 = 本番の major、search_path に alc_api が入っている)。全部の表・関数が一斉に変わったら、
# migration ではなく版か search_path を疑う。
#
# 流すのは ci/rls_state.sql (カタログを読む SELECT 1 文) だけで、DB は何も変更しない。
set -euo pipefail
cd "$(dirname "$0")/.."

state=$(psql -X -v ON_ERROR_STOP=1 -q -At -f ci/rls_state.sql)
if [ -z "$state" ] || [ "$(printf '%s\n' "$state" | wc -l)" != "1" ]; then
  echo "ci/rls_state.sql の出力が 1 行ではありません (空、または複数行)" >&2
  exit 1
fi
printf '%s\n' "$state" | jq -S 'del(.tables[].owner)' > ci/expected_rls_state.json.tmp
mv ci/expected_rls_state.json.tmp ci/expected_rls_state.json
echo "ci/expected_rls_state.json を作り直しました ($(wc -c < ci/expected_rls_state.json) bytes)"
