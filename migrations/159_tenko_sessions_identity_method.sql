-- 点呼の記録に、運転者の「本人確認の方法」を記録する列を足す
-- Refs ippoan/alc-app#387
--
-- 点呼の最初に運転者の本人確認をするが、どの方法で通したのか (運転免許証 / 社員証の IC カード /
-- 手入力 …) は、これまでどこにも記録していなかった。
--
-- オーナー決定: 社員証の IC カードで本人確認した回でも、一時的に IT点呼 (154) を許す。
-- 将来 IC カードを外したあと、後から見分けられるように、IC カードで通したことを記録に残す。
--
-- identity_method の値:
--   'license'      = 運転免許証の読み取り
--   'ic_card'      = その端末に繋いだ機体で読んだ社員証の IC カードの打刻から始めた
--   'remote_punch' = 別の端末の打刻の案内から始めた (その端末ではカードを読んでいない)
--   'nfc_card'     = 免許証以外のカードの読み取り
--   'manual'       = 手入力
--   NULL           = 記録なし (この列より前の記録、または方法を送らない端末・経路)
--
-- 運転者の本人確認の方法であって、運行管理者の判定の確認の方法 (157 の manager_judgment_method)
-- とは別。端末の自己申告をそのまま記録するだけで、認可の判断には使わない。
--
-- tenko_records には足さない: 作成後の UPDATE / DELETE を trigger が拒否する表で、
-- 記録の置き場は tenko_sessions の 1 列で足りる。
--
-- 足すだけ (expand)。既存の行は NULL のまま (backfill しない)。古い backend は余剰の列を
-- 読まず、INSERT / UPDATE でこの列を指定しないので、この migration だけ先に入っても動く。
-- RLS のポリシー (153 の tenant_isolation_tenko_sessions) は行単位なので変えない。
-- GRANT は表単位で既に付いているので足さない。index は足さない。既存の制約は変えない。
--
-- IF NOT EXISTS は付けない: 同名で形の違う列が既に在ったら、黙って素通りせずここで落とす
-- (migration は 1 transaction なので DB は変わらない)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (DB は無変更でデプロイが止まるだけなので、やり直せる)。
-- SET LOCAL なので、この migration の transaction の中だけに効く。
-- statement_timeout は付けない (153〜157 と揃える。既定値の無い列の追加は表を書き換えない)。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.tenko_sessions
    ADD COLUMN identity_method TEXT
        CHECK (identity_method IS NULL
               OR identity_method IN ('license', 'ic_card', 'remote_punch', 'nfc_card', 'manual'));

COMMENT ON COLUMN alc_api.tenko_sessions.identity_method IS
    '運転者の本人確認の方法 (端末の自己申告。認可の判断には使わない)。license = 運転免許証の読み取り / ic_card = その端末に繋いだ機体で読んだ社員証の IC カードの打刻から始めた / remote_punch = 別の端末の打刻の案内から始めた / nfc_card = 免許証以外のカードの読み取り / manual = 手入力 / NULL = 記録なし。運行管理者の判定の確認の方法 (manager_judgment_method) とは別';
