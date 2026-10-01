-- 点呼方法に 'IT点呼' を足す
-- Refs ippoan/alc-app#387
--
-- IT点呼 は、通常点呼の流れ (運行者端末での測定) の最後に運行管理者と通話する方法。
-- 保存の経路は通常点呼と同じ (測定の完了 PUT から tenko_sessions / tenko_records を作る)。
--
-- 144 の tenko_method CHECK は '自動点呼' / '通常点呼' / '遠隔点呼' の 3 値だったので、
-- 4 値目の 'IT点呼' を追加する。tenko_records.tenko_method には CHECK が無い
-- (migration 015 は DEFAULT のみ) ので触らない。

-- 1. CHECK の張り直し。制約名を決め打ちせず pg_constraint から引く (理由は 144 の冒頭)。
--    「tenko_method 列の CHECK がちょうど 1 個」でなければ RAISE EXCEPTION で落とす。
DO $$
DECLARE
    v_conname TEXT;
    v_count   INT;
BEGIN
    SELECT count(*), min(c.conname)
      INTO v_count, v_conname
      FROM pg_constraint c
      JOIN pg_attribute a
        ON a.attrelid = c.conrelid
       AND a.attnum = ANY (c.conkey)
     WHERE c.conrelid = 'alc_api.tenko_sessions'::regclass
       AND c.contype = 'c'
       AND a.attname = 'tenko_method';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'migration 154: tenko_sessions の tenko_method 列に掛かる CHECK 制約が % 個見つかりました (1 個であるはず)。'
            ' migration 履歴の外で制約が張り替えられている可能性があります。'
            ' pg_constraint を確認してから再実行してください。',
            v_count;
    END IF;

    RAISE NOTICE 'migration 154: tenko_method CHECK 制約 "%" を DROP します', v_conname;
    EXECUTE format('ALTER TABLE alc_api.tenko_sessions DROP CONSTRAINT %I', v_conname);
END
$$;

-- 張り直しは新規作成なので名前が衝突しない。既定命名に揃えておく。
ALTER TABLE alc_api.tenko_sessions
    ADD CONSTRAINT tenko_sessions_tenko_method_check
    CHECK (tenko_method IN ('自動点呼', '通常点呼', '遠隔点呼', 'IT点呼'));

-- 2. 通常点呼の冪等の部分 unique (migration 141) を掛け直す
--    (DROP と CREATE は同じ transaction なので index が無い瞬間は無い)。
--    DROP に IF EXISTS を付けない: 名前が違っていたら黙って旧 index を残さず、ここで落とす。
--
--    変える点は 2 つ:
--    * 鍵に is_dev (migration 153) を足す。乗務員は dev と本番で共有なので、
--      (employee_id, started_at) が軸をまたいで衝突すると、backend の対象なしの
--      ON CONFLICT DO NOTHING が「見えない側の行」を理由に黙って記録を捨てる。
--    * 述語に 'IT点呼' を足す。IT点呼 は通常点呼と同じ保存経路を通るので同じ冪等が要るが、
--      tenko_type が pre_operation / post_operation の IT点呼 は 141 の述語の外になる。
--
--    述語は 141 の上位集合で、鍵は 141 より緩い (列が増える)。'IT点呼' の行はこの時点で
--    0 件 (上の CHECK が今まで拒否していた) なので、既存の行で張れなくなることは無い。
--    backend は対象を指定しない ON CONFLICT DO NOTHING なので、古い版もそのまま動く。
DROP INDEX alc_api.uq_tenko_sessions_normal_flow_measurement;
DROP INDEX alc_api.uq_tenko_sessions_normal_flow_employee_started;

-- 同じ測定への完了 PUT が 2 回届いても記録は 1 組
CREATE UNIQUE INDEX uq_tenko_sessions_normal_flow_measurement
    ON alc_api.tenko_sessions (measurement_id, is_dev)
    WHERE tenko_type = 'normal' OR tenko_method IN ('通常点呼', 'IT点呼');

-- オンラインの完了 PUT が落ちてオフライン保存へ回り、測定がもう 1 件できる経路。
-- started_at = measured_at が同じなのでここで弾ける。
CREATE UNIQUE INDEX uq_tenko_sessions_normal_flow_employee_started
    ON alc_api.tenko_sessions (employee_id, started_at, is_dev)
    WHERE tenko_type = 'normal' OR tenko_method IN ('通常点呼', 'IT点呼');
