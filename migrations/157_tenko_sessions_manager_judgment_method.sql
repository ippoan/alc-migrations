-- 運行管理者の判定に「確認の方法」(通話 / 対面) を記録する列を足す
-- Refs ippoan/alc-app#387
--
-- IT点呼 は、通常点呼の流れ (本人確認 → 測定 → 保存) の最後に運行管理者と通話する方法 (154)。
-- 保存の時点で tenko_sessions と tenko_records が tenko_method = 'IT点呼' で作られ、
-- 運行管理者の判定 (148 の manager_judgment) が付くまでは未完了として扱う。
--
-- オーナー決定: 運行管理者は判定を確定するときに、通話で確認したのか、本人が来て対面で
-- 確認したのかを選ぶ。その選択を、148 の manager_judgment / manager_judgment_reason /
-- manager_judgment_by と並べて tenko_sessions に記録する。
--
-- manager_judgment_method の値:
--   'it'        = 通話で確認した
--   'in_person' = 対面で確認した
--   NULL        = 未確定、または IT点呼 でない
--
-- tenko_method を書き換える案は採らない:
--   * tenko_method の CHECK (154) に対面を表す値が無い
--   * 冪等用の部分 unique (154) の述語から行が外れる
--   * tenko_records は作成後の UPDATE / DELETE を trigger が拒否するので、
--     書き換えられない記録側の tenko_method と食い違う
-- 書けるのは tenko_sessions 側だけなので、判定と同じ表に列を足す。
--
-- 足すだけ (expand)。既存の行は NULL のまま (backfill しない)。古い backend は余剰の列を
-- 読まず、INSERT / UPDATE でこの列を指定しないので、この migration だけ先に入っても動く。
-- RLS のポリシー (153 の tenant_isolation_tenko_sessions) は変えない。index は足さない。
--
-- IF NOT EXISTS は付けない: 同名で形の違う列が既に在ったら、黙って素通りせずここで落とす
-- (migration は 1 transaction なので DB は変わらない)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (DB は無変更でデプロイが止まるだけなので、やり直せる)。
-- SET LOCAL なので、この migration の transaction の中だけに効く。
-- statement_timeout は付けない (153〜156 と揃える。既定値の無い列の追加は表を書き換えない)。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.tenko_sessions
    ADD COLUMN manager_judgment_method TEXT
        CHECK (manager_judgment_method IN ('it', 'in_person'));
