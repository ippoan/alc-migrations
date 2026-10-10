#!/usr/bin/env bash
# ci/check_contract.sh の陰性・陽性の対照
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# expect <pass|fail> <題> <SQL>
expect() {
  want=$1; title=$2
  printf '%s\n' "$3" >"$tmp/m.sql"
  if bash "$here/check_contract.sh" "$tmp/m.sql" 2>/dev/null; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then echo "ok   - $title"; else echo "FAIL - $title (want $want, got $got)"; fail=1; fi
}

# 通る (足すだけ・作り直し型)
expect pass 'CREATE TABLE だけ' 'CREATE TABLE a (id int); ALTER TABLE a ADD COLUMN b int;'
expect pass 'DROP POLICY IF EXISTS' 'DROP POLICY IF EXISTS p ON a; CREATE POLICY p ON a USING (id > 0);'
expect pass 'DROP INDEX' 'DROP INDEX i;'
expect pass 'DROP FUNCTION / TRIGGER / VIEW' 'DROP FUNCTION IF EXISTS f(); DROP TRIGGER IF EXISTS t ON a; DROP VIEW IF EXISTS v;'
expect pass 'ALTER TABLE ... DROP CONSTRAINT' 'ALTER TABLE a DROP CONSTRAINT IF EXISTS c, ADD CONSTRAINT c CHECK (id > 0);'
expect pass 'ALTER COLUMN ... DROP NOT NULL' 'ALTER TABLE a ALTER COLUMN b DROP NOT NULL;'
expect pass 'ALTER COLUMN ... DROP DEFAULT' 'ALTER TABLE a ALTER COLUMN b DROP DEFAULT;'
expect pass '行コメントの中の DROP' '-- DROP TABLE a;
CREATE TABLE b (id int);'
expect pass 'ブロックコメントの中の DROP / RENAME' '/* DROP TABLE a;
   RENAME x */
CREATE TABLE b (id int);'
expect pass '識別子の一部 (renamed_at / drop_flag)' 'ALTER TABLE x ADD COLUMN renamed_at timestamptz, ADD COLUMN drop_flag bool;'

# 落ちる (データを失う・名前が変わる)
expect fail 'DROP TABLE' 'DROP TABLE a;'
expect fail 'DROP TABLE IF EXISTS (小文字・改行)' 'drop table if exists
  a;'
expect fail 'DROP SCHEMA' 'DROP SCHEMA s CASCADE;'
expect fail 'DROP TYPE' 'DROP TYPE t;'
expect fail 'TRUNCATE' 'TRUNCATE x;'
expect fail 'ALTER TABLE ... DROP COLUMN' 'ALTER TABLE x DROP COLUMN a;'
expect fail 'ALTER TABLE ... DROP COLUMN IF EXISTS' 'ALTER TABLE x DROP COLUMN IF EXISTS a;'
expect fail 'ALTER TABLE ... DROP <名前> (COLUMN 省略)' 'ALTER TABLE x DROP a;'
expect fail 'DROP NOT NULL と DROP COLUMN の混在' 'ALTER TABLE x ALTER COLUMN a DROP NOT NULL,
  DROP COLUMN b;'
expect fail 'ALTER TABLE ... RENAME COLUMN' 'ALTER TABLE x RENAME COLUMN a TO b;'
expect fail 'ALTER TABLE ... RENAME TO' 'ALTER TABLE x RENAME TO y;'
expect fail 'コメントの後ろの文' '-- 説明
DROP TABLE i; -- 後ろ'

# 引数なし (未適用が 0 件) は通る
if bash "$here/check_contract.sh"; then echo "ok   - 引数なし"; else echo "FAIL - 引数なし"; fail=1; fi

exit "$fail"
