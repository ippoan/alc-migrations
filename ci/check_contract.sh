#!/usr/bin/env bash
# contract (データを失う・名前が変わる) の migration を見つける。引数は SQL ファイル。
# 止めるもの (大小文字を無視。コメント -- 行末・/* */ は除く):
#   DROP TABLE / DROP SCHEMA / DROP TYPE、TRUNCATE、RENAME (TO / COLUMN ほか)、
#   ALTER TABLE ... DROP [COLUMN] <名前> (CONSTRAINT / DEFAULT / NOT NULL / IDENTITY / EXPRESSION が続かないもの)
# 止めないもの (作り直し型): DROP POLICY / INDEX / FUNCTION / TRIGGER / VIEW / CONSTRAINT、
#   ALTER COLUMN ... DROP NOT NULL / DEFAULT
# 当たれば該当の箇所を stderr に出して exit 1。何も書かない。接続しない。
set -euo pipefail

bad=0
for f in "$@"; do
  # 文字列の中の -- も落とす (見逃すのは同じ行のその後ろだけ)。空白は 1 つにまとめて見る
  if ! perl -0777 -e '
    my $f = shift;
    local $/; open(my $fh, "<", $f) or die "$f: $!";
    my $s = <$fh>;
    $s =~ s{/\*.*?\*/}{}gs;
    $s =~ s/--[^\n]*//g;
    $s =~ s/\s+/ /g;
    my @hit;
    while ($s =~ /(\bDROP\s+(?:TABLE|SCHEMA|TYPE)\b.{0,40})/ig) { push @hit, $1 }
    while ($s =~ /(\bTRUNCATE\b.{0,40})/ig)                      { push @hit, $1 }
    while ($s =~ /(\bRENAME\b.{0,40})/ig)                        { push @hit, $1 }
    while ($s =~ /\bALTER\s+TABLE\b([^;]*)/ig) {
      my $seg = $1;
      # 後ろの DROP を食わないよう、表示用の続きは先読みで取る
      while ($seg =~ /\bDROP\s+(\w+)(?=(.{0,40}))/ig) {
        next if uc($1) =~ /^(?:CONSTRAINT|DEFAULT|NOT|IDENTITY|EXPRESSION)$/;
        push @hit, "ALTER TABLE ... DROP $1$2";
      }
    }
    exit 0 unless @hit;
    print STDERR "contract: $f\n";
    print STDERR "  $_\n" for @hit;
    exit 1;
  ' "$f"; then
    bad=1
  fi
done
exit "$bad"
