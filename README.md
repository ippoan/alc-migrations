# alc-migrations

alc-api の DB migration (SQL) を埋め込んだ薄い crate。migration だけを monolith から分け、CI を速く回すための repo。
SQL は rust-alc-api の `03e0571` から 1 バイトも変えずに移してある (sqlx の checksum は SQL 本文だけで決まるため、本番の `_sqlx_migrations` とそのまま一致する)。

## 版の規約
`0.<最新の migration 番号>.<patch>`。migration を足したら minor を上げ、SQL 以外の変更は patch を上げる。

## 使い方

git 依存で読む (rev 固定)。crates.io には出していない。

```toml
[dev-dependencies]
alc-migrations = { git = "https://github.com/ippoan/alc-migrations", rev = "<コミットの SHA>" }
```

```rust
alc_migrations::MIGRATOR.run(&pool).await?;
```

テスト用 DB 向けに `alc_migrations::INIT_LOCAL_DB` / `LOCAL_APP_GRANTS` (init / grants の SQL) も公開している。本番では使わない。

`alc_migrations::RLS_INVARIANTS_QUERY` は RLS の不変条件の検査 (`ci/check_rls_invariants.sql` そのもの。1 文の SELECT で、0 行なら合格)。何も変更しないので本番でも流せる。

`alc_migrations::RLS_INVARIANT_CHECKS` はその検査の題の一覧 (`(検査の番号, 題)`。番号は検査 SQL の `check_no` と同じで、一致は tests が見る)。違反が 0 件のときも「どの検査を流したか」を返すために使う。
`alc_migrations::RLS_STATE_QUERY` は RLS まわりのいまの状態 (`ci/rls_state.sql` そのもの。1 文の SELECT で、1 行 1 列の JSON `state`)。`alc_api` schema のカタログから、表ごとの RLS・FORCE・所有者・ポリシーの式・`alc_api_rt` の権限 (状態が同じ表は 1 組にまとめる)、view、`SECURITY DEFINER` の関数、sequence を返す。合否は決めない (合否は検査 SQL だけが決める)。表の行は読まず、何も変更しないので本番でも流せる。
`alc_migrations::RLS_EXPECTED_STATE` は期待する RLS の状態 (`ci/expected_rls_state.json` そのもの)。全 migration を空の DB に 0 から当て、`RLS_STATE_QUERY` を流した出力から、各組の `owner` (所有者のロール名。環境で違う) を除き、key を並べて整形した JSON。実物と比べる側も `owner` を落としてから比べる (`jq -S 'del(.tables[].owner)'` と同じ規則)。ポリシーの式と関数の signature の文字列は PostgreSQL の版と接続の search_path に依るので、全部の表・関数が一斉に食い違ったら、まず版か search_path を疑う。
`ci/` のうち crate に入るのはこの 3 本だけ。

バイナリ (`cli` feature):

```bash
DATABASE_URL=postgresql://... cargo run --features cli --bin alc-migrate
```

## 取り込みの手順
1. migration を足し、`Cargo.toml` の版を migration 番号に合わせて PR → merge
2. rust-alc-api の `Cargo.toml` で、この crate の `rev` を merge 後の main のコミットの SHA に上げる

## 本番に流す
本番の DB に流すのは `.github/workflows/migrate.yml` の**手動実行**だけ (main のみ・environment `production` の承認)。
runner から直接 DB に繋ぐ (GCP は使わない)。接続文字列は org の secret `ALC_MIGRATE_DATABASE_URL` (alc-migrations と rust-alc-api にだけ公開。
repo に値・ホスト名は書かない)。environment `production` の承認が要り、main でしか動かない。
`alc-migrate` を build し、`--status` (読むだけ) → 適用 → `--check` (未適用 0) の順に実行して、各段の出力を step summary に出す。

`alc-migrate` の引数: なし = 適用 / `--status` = 未適用の version と description を 1 行ずつ出して `pending: <件数>` (exit 0) /
`--check` = `--status` と同じで、未適用が 1 件以上なら exit 1。接続文字列・接続先は出さない。

rust-alc-api は `rev` を上げるだけ。上げてよい rev は、最後に本番へ流した SHA 以前。
contract (消す・名前を変える) の migration は、rust-alc-api と全 worker が新スキーマに移った後に本番へ流す (release から切り離されたので人の判断)。

tag は使わない。crates.io には出さない (`Cargo.toml` は `publish = false`)。

## ロールと RLS (migration 158〜)

本番では、migration を流すロール `alc_api_app` が `alc_api` の全表の所有者で、backend は所有者でない実行用ロール `alc_api_rt` で繋ぐ。
PostgreSQL は `FORCE ROW LEVEL SECURITY` の無い表では所有者にポリシーを適用しないので、RLS が掛かるのは `alc_api_rt` の接続だけ。
migration 118〜120・137 のコメントの「`alc_api_app` は非所有者」は誤り (適用済みの migration は直せないので、ここに記す)。

migration を書くときの決まり:

- 新しい表は RLS を有効にする。RLS 無しの表を足すなら、`ci/check_rls_invariants.sql` の許可リストに足し、理由をそこのコメントに書く
- ポリシーに `TO <role>` を書かない (宛先は PUBLIC)。書くなら `alc_api_rt` を含める。含めないと backend からは 1 行も見えない
- `alc_api_rt` への表・sequence・関数の権限は、158 の `ALTER DEFAULT PRIVILEGES` で自動で付く。migration に `GRANT … TO alc_api_rt` を書かなくてよい (`GRANT … TO alc_api_app` は今までどおり書く。CI の `postgres` の軸では `alc_api_app` が所有者でないため)
- 関数を PUBLIC から `REVOKE` したら、`alc_api_rt` に `GRANT EXECUTE` を明示する (`REVOKE … FROM PUBLIC` は `alc_api_rt` の EXECUTE を消さないが、誰が呼べるかを読んで分かるようにする)
- 新しい `SECURITY DEFINER` の関数は 158 の形で作る (`SET search_path = alc_api`、PUBLIC から `REVOKE`)。view / materialized view を作らない。式が `true` のポリシー (`USING (true)` / `WITH CHECK (true)`) を書かない。どれも `ci/check_rls_invariants.sql` の検査 6〜8 が落とす (許可リストは、いま在るものを固定しているだけなので足さない)。式の `COALESCE` の最後の引数が列 `tenant_id` そのもの (`tenant_id = COALESCE(<テナントの設定>, tenant_id)`) のポリシーも書かない (検査 9。この 1 つの綴りだけを捕まえる。許可リストなし)
- RLS の状態 (表・ポリシー・`SECURITY DEFINER` の関数・sequence・権限) を変えたら、`ci/update_expected_rls_state.sh` で `ci/expected_rls_state.json` を作り直し、差分を同じ PR に入れる (replay と同じ手順で作った DB に `PG*` の環境変数で繋いで流す)
- migration の中の DML は所有者として動くので、RLS の影響を受けない。ただし FORCE 付きの表は受ける (tenant context を立てないと 0 行・拒否になる)
- `SECURITY DEFINER` 関数も所有者として動く。FORCE 付きの表に触る関数は、中で tenant context を立てる

CI の replay job は「migration を流すロール」の 2 つの軸で回る:

| 軸 | 表の所有者 | RLS を確かめるロール | 見つけるもの |
|---|---|---|---|
| `postgres` | `postgres` | `alc_api_app` | migration の GRANT 漏れ (所有者には GRANT が要らないので、もう片方の軸では見つからない) |
| `alc_api_app` | `alc_api_app` (本番と同じ) | `alc_api_rt` | superuser でないと通らない文、所有者だから素通りしている RLS |

どちらの軸でも `ci/check_rls_invariants.sql` を流し、「ポリシーを書いたが backend に効いていない」を落とす
(所有者の資格を取れる / 効くポリシーが無い / RLS 無しの表が増えた / 権限が付いていない /
view が在る / PUBLIC が呼べる `SECURITY DEFINER` の関数が増えた / 式が `true` のポリシーが増えた / `COALESCE` の最後の引数が列 `tenant_id` そのもののポリシーが増えた)。
この SQL は 1 文の SELECT (違反を 1 行ずつ返す。0 行なら合格) で、何も変更しないので本番でもそのまま流せる。
CI は同じファイルを実行用ロール (`SET ROLE alc_api_rt`) でも流し、違反を作ったときに行が出ること (陽性対照) も確かめる。
`ci/rls_state.sql` も流し、superuser と実行用ロールで出力が完全に同じこと・表の数の自己整合・状態を変えれば出力が変わること (陽性対照) を確かめる。
さらに、どちらの軸でも「実物 = `ci/expected_rls_state.json`」を比べる (`owner` を除いてあるので、2 軸とも同じファイルと比べる)。食い違えば差分を表示して落とすので、RLS の状態を変える migration は必ずこのファイルの差分として PR に現れる。

ここまではカタログを読む検査で、式が `true` ではないが間違っているポリシー (別の GUC 名・余計な `OR`・`IS NOT NULL` など) は落とせない。
それは `ci/check_rls_rows.sql` が、実際の行で確かめる (crate には入れない。CI 専用)。

- 対象: `alc_api` schema の `tenant_id` 列を持つ表の全部。カタログから引くので、表を足しても検査に手を入れなくてよい
- 流すロール: どちらの軸でも実行用ロール (`SET LOCAL ROLE alc_api_rt`)。行を入れるのは superuser。1 transaction で流して `ROLLBACK` する
- 確かめること: テナントを 2 つ作って各表に 1 行ずつ入れ、a. テナント未設定では 1 行も読めない / b. テナント A からは A の行だけが見える (自分の行も見えない空振りは合格に数えない) / c. テナント A から B の `tenant_id` での INSERT が 42501
- 違反を 1 行ずつ返す (0 行なら合格)。行を入れられない表も違反として出す (黙って飛ばさない)。確かめた表の数が「`tenant_id` を持つ表の数 − 例外」と合うことも、検査の中で数える
- 行は NOT NULL で既定値の無い列だけを、カタログから自動で埋める (外部キーは親の行、`列 IN (…)` の CHECK は許される値の 1 つめ、ほかは型から)。**複数の列にまたがる CHECK を持つ表を足すと「行を入れられない」の違反が出る** — そのときだけ、ファイルの中の種 (列と値の指定。いま `users`・`tenko_schedules`・`notify_recipients` の 3 表) に足す
- 例外 (いま在るものを固定しているだけ。足さない)。例外の表が例外のとおりに振る舞わなくなったら、それも違反として出す
  - RLS が無効 (読みも書きも通る): `vehicle_settings_dumps` (`check_rls_invariants.sql` の検査 3 の許可リストと同じ)
  - 読み (全部のテナントの行が見える): `tenko_call_numbers`・`tenko_call_drivers`・`device_registration_requests` (SELECT が `USING (true)`。検査 8 の許可リストと同じ)
- 書きの保留 (2 表。例外として認めるか・ポリシーを直すかは未判断。Refs ippoan/rust-alc-api#727): `device_registration_requests` (INSERT の WITH CHECK が `status = 'pending'` だけ)・`access_requests` (INSERT の WITH CHECK が `user_id = app.current_user_id` だけ)。式は `true` ではないが `tenant_id` を見ないので、別のテナントの `tenant_id` で INSERT できる。`check_rls_invariants.sql` の許可リストに対応するものは無い。**CI は落とさず、通ったことを確かめたうえで毎回警告を出す** (psql の `WARNING` と、GitHub Actions の注釈)。通らなくなったら違反として出すので、そのとき保留から外す。足さない
- 対象外: `tenant_id` 列を持たない表 (親の表を subquery で引くポリシーの 5 表と、`tenants`・`_sqlx_migrations`)。理由はファイルの冒頭

CI は陽性対照として、`USING (tenant_id IS NOT NULL)` のポリシー (検査 8 では落ちない壊し方) を足すと違反の行が出ることも確かめる。

PR を出す前に branch で CI を流す (PR は緑になると自動でマージされる): `gh workflow run CI --repo ippoan/alc-migrations --ref <branch>`。
実 DB の replay job まで走るので、手元の DB は要らない (この経路では safety と auto-merge は動かない)。
`--ref main` では流さない (main への push の run と同じ concurrency の group になり、片方が止まる)。branch を指定して使う。

## License
MIT
