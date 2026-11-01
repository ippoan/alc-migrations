-- 打刻 (hub_measurements) から測定 (measurements) へのつなぎを本物の列にする
--
-- 打刻の一覧と CSV は、payload の文字列 `measurement_id` を正規表現で uuid の形か見てから測定に結び、
-- tenant・is_dev・社員が一致するものだけを点呼の判定に使っている。つなぎが JSON の中にあるので
-- 外部キーが無く、点呼のセッションまで 3 表を文字列でまたいでいる。
-- 列 `measurement_id` を足し、測定を (tenant_id, id) の複合の外部キーで指す。書き手 (people-worker の
-- 取り込み) は、この migration の後に payload の値を検査してこの列にも書くようにする。
--
-- * NULL 可。測定に結ばない打刻 (点呼にしない打刻・旧データ・体温などの生の記録) は NULL のまま
-- * ON DELETE は指定しない (既定の拒否)。測定は消さない運用
-- * 既存の行は、いまの一覧の SQL と同じ条件で埋める: kind が timecard / license、payload の値が uuid の形、
--   同じ tenant・is_dev の測定が在り、その測定の社員が打刻の社員 (payload の employee_id → カードの台帳 →
--   免許証番号の順) と一致するもの。条件に合わない行は NULL のまま (一覧で点呼に結ばれていない行と同じ)
-- * index は (tenant_id, measurement_id) の部分 index。結ばれた行だけを持つ
-- * 表の所有者で流すので RLS は効かない (hub_measurements・measurements は FORCE でない)

SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.hub_measurements ADD COLUMN measurement_id UUID;

ALTER TABLE alc_api.hub_measurements
    ADD CONSTRAINT hub_measurements_measurement_id_fkey
    FOREIGN KEY (tenant_id, measurement_id) REFERENCES alc_api.measurements (tenant_id, id);

UPDATE alc_api.hub_measurements hm
   SET measurement_id = m.id
  FROM alc_api.measurements m
 WHERE hm.kind IN ('timecard', 'license')
   AND m.id = CASE WHEN hm.payload->>'measurement_id'
                        ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                   THEN (hm.payload->>'measurement_id')::uuid END
   AND m.tenant_id = hm.tenant_id
   AND m.is_dev = hm.is_dev
   AND m.employee_id = COALESCE(
           CASE WHEN hm.payload->>'employee_id'
                     ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                THEN (hm.payload->>'employee_id')::uuid END,
           (SELECT tc.employee_id FROM alc_api.timecard_cards tc
             WHERE tc.tenant_id = hm.tenant_id
               AND tc.card_id = lower(replace(btrim(hm.payload->>'card_id'), ':', ''))),
           (SELECT e.id FROM alc_api.employees e
             WHERE e.tenant_id = hm.tenant_id
               AND e.nfc_id = COALESCE(hm.payload->>'card_id', hm.payload->>'nfc_id'))
       );

CREATE INDEX hub_measurements_tenant_measurement
    ON alc_api.hub_measurements (tenant_id, measurement_id)
    WHERE measurement_id IS NOT NULL;
