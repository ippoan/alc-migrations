-- hub_measurements の旧 3 列 unique (tenant_id, device_id, seq) を落とす
-- Refs ippoan/alc-app#387
--
-- 153 と 155 が予告していた「別 migration」(contract)。
--   * 126: UNIQUE (tenant_id, device_id, seq) を張った (再送重複の排除)
--   * 153: is_dev 列を足した (dev端末の記録を本番の記録と分ける軸)
--   * 155: is_dev を含む 4 列の unique index hub_measurements_tenant_device_seq_is_dev を「足した」
-- 3 列が残っているあいだは、同じ端末の同じ seq が dev の軸と本番の軸の両方で届くと
-- 一意違反になる。ここで 3 列を落とし、再送の重複排除を 4 列の index だけに任せる。
--
-- 前提: backend が ON CONFLICT (tenant_id, device_id, seq, is_dev) へ切り替わって
-- 本番に出た後に流す。3 列の ON CONFLICT (tenant_id, device_id, seq) を使う古い backend は、
-- この migration の後は制約を推論できず INSERT が全件落ちる (42P10)。
--
-- 待たされるのは hub_measurements だけ (ALTER TABLE が ACCESS EXCLUSIVE を取る)。
-- 表の走査も書き換えも無いので、ロックが取れればすぐ終わる。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (DB は無変更でデプロイが止まるだけなので、やり直せる)。
-- SET LOCAL なので、この migration の transaction の中だけに効く。
-- statement_timeout は付けない (153〜155 と揃える。DROP CONSTRAINT は表を走査しないので、長引くのはロック待ちだけ)。
SET LOCAL lock_timeout = '10s';

-- 制約名を決め打ちせず pg_constraint から引く (理由は 144 の冒頭。126 は名前を指定して
-- いないので、実名は DB が付けた既定名で、ここからは確かめられない)。
-- 前提が 1 つでも違えば RAISE EXCEPTION で落とす (migration は 1 transaction なので
-- DB は変わらない)。
DO $$
DECLARE
    v_conname TEXT;
    v_count   INT;
    v_found   TEXT[];
BEGIN
    -- 0. 4 列の unique index (155) が在り、unique で、有効で、部分 index でないこと。
    --    これが無い DB で 3 列を落とすと、再送の重複排除が全部消える。
    IF NOT EXISTS (
        SELECT 1
          FROM pg_index i
         WHERE i.indexrelid = to_regclass('alc_api.hub_measurements_tenant_device_seq_is_dev')
           AND i.indrelid = 'alc_api.hub_measurements'::regclass
           AND i.indisunique
           AND i.indisvalid
           AND i.indpred IS NULL
           AND i.indnkeyatts = 4
           AND (
               SELECT array_agg(a.attname::TEXT)
                 FROM pg_attribute a
                WHERE a.attrelid = i.indrelid
                  AND a.attnum = ANY (i.indkey::INT2[])
           ) @> ARRAY['tenant_id', 'device_id', 'seq', 'is_dev']
    ) THEN
        RAISE EXCEPTION
            'migration 156: alc_api.hub_measurements_tenant_device_seq_is_dev が、hub_measurements の'
            ' (tenant_id, device_id, seq, is_dev) に掛かる有効な unique index として見つかりません'
            ' (migration 155 が作るはず)。この状態で 3 列の unique を落とすと再送の重複排除が無くなります。'
            ' pg_index (indisunique / indisvalid / indpred) を確認してから再実行してください。';
    END IF;

    -- 1. 鍵の列がちょうど tenant_id / device_id / seq の 3 つである UNIQUE 制約。
    --    「ちょうど 1 個」でなければ落とす (0 個 = 既に落ちている・別の形に張り替えられた、
    --    2 個以上 = 履歴の外で足された)。
    SELECT count(*),
           min(c.conname),
           coalesce(array_agg(c.conname::TEXT ORDER BY c.conname), '{}')
      INTO v_count, v_conname, v_found
      FROM pg_constraint c
     WHERE c.conrelid = 'alc_api.hub_measurements'::regclass
       AND c.contype = 'u'
       AND cardinality(c.conkey) = 3
       AND (
           SELECT array_agg(a.attname::TEXT)
             FROM pg_attribute a
            WHERE a.attrelid = c.conrelid
              AND a.attnum = ANY (c.conkey)
       ) @> ARRAY['tenant_id', 'device_id', 'seq'];

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'migration 156: hub_measurements の (tenant_id, device_id, seq) ちょうど 3 列に掛かる UNIQUE 制約が'
            ' % 個見つかりました: % (migration 126 が張った 1 個であるはず)。'
            ' migration 履歴の外で制約が落とされた・張り替えられた可能性があります。'
            ' pg_constraint を確認してから再実行してください。',
            v_count, v_found;
    END IF;

    -- IF EXISTS は付けない (名前が違って黙って何も起きない、を避ける)。
    -- 制約を落とすと、その裏の unique index も一緒に消える (別の DROP INDEX は要らない)。
    RAISE NOTICE 'migration 156: hub_measurements の 3 列 UNIQUE 制約 "%" を DROP します', v_conname;
    EXECUTE format('ALTER TABLE alc_api.hub_measurements DROP CONSTRAINT %I', v_conname);
END
$$;
