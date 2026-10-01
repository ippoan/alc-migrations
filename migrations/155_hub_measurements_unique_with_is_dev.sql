-- hub_measurements の再送冪等の鍵に is_dev を足した unique index を「足す」
-- Refs ippoan/alc-app#387
--
-- 同じ端末の同じ seq が dev と本番の両方にあり得るようにするための土台 (is_dev は
-- migration 153)。既存の UNIQUE (tenant_id, device_id, seq) (migration 126) は残すので、
-- この migration の時点ではまだ 3 列で弾かれる。古い backend は
-- ON CONFLICT (tenant_id, device_id, seq) で 3 列の制約を推論しているため、
-- 3 列を落とすのは backend が 4 列へ切り替わって本番に出た後の別 migration で行う。
--
-- 153 と分けてあるのは、migration がファイルごとに別の transaction で走るため。
-- 153 は 8 表に ACCESS EXCLUSIVE を取るので、同じ transaction で index を作ると、
-- 作っているあいだ 8 表の読み書きが全部止まる。ここで待たされるのは
-- hub_measurements への書き込みだけ (読み取りは通る)。
--
-- CONCURRENTLY にしていないのは migration が transaction 内で走るため (135 と同じ)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (DB は無変更でデプロイが止まるだけなので、やり直せる)。
-- SET LOCAL なので、この migration の transaction の中だけに効く。
-- statement_timeout は付けない (index の作成を途中で切らないため)。
SET LOCAL lock_timeout = '10s';

CREATE UNIQUE INDEX hub_measurements_tenant_device_seq_is_dev
    ON alc_api.hub_measurements (tenant_id, device_id, seq, is_dev);
