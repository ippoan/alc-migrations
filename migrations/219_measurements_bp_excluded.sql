-- 測定台の血圧を「本人の測定ではない」として外す印 (足すだけ。Refs ippoan/alc-app#676)
--
-- 自動点呼の血圧は 1 回に限り測り直せる (2025/10/6 FAQ)。測定台では同じ運転者が測定の有効時間内に 2 回まで
-- (最初 + 測り直し 1 回) 測れ、点呼には新しい方を使う (alc-measurements-worker)。測定台で人が入れ替わり
-- (テレコ) 別の人の血圧が自分の分に入ったときは、運行管理者がその測定を理由と氏名を付けて外す。外した測定は
-- 回数にも点呼にも入らない。測定そのものは消さずに残す (外した時刻・理由・人が記録になる)。
--
-- 4 列とも NULL 可・DEFAULT なし (既存行と既存の INSERT / UPDATE を壊さない)。外す口だけが 4 列を同時に書く。
-- 外したかどうかは bp_excluded_at で見る。外した人は、ログインの利用者なら user_id、氏名は必ず残す。
ALTER TABLE alc_api.measurements
    ADD COLUMN bp_excluded_at TIMESTAMPTZ NULL,
    ADD COLUMN bp_excluded_reason TEXT NULL,
    ADD COLUMN bp_excluded_by_name TEXT NULL,
    ADD COLUMN bp_excluded_by_user_id UUID NULL;

-- 外した印は時刻・理由・氏名がそろう (どれかだけの行を作らない)。btrim(NULL) は NULL で CHECK を通ってしまうので
-- IS NOT NULL を明示する。既存行は全部 NULL なので通る
ALTER TABLE alc_api.measurements
    ADD CONSTRAINT measurements_bp_excluded_check CHECK (
        (bp_excluded_at IS NULL AND bp_excluded_reason IS NULL AND bp_excluded_by_name IS NULL
            AND bp_excluded_by_user_id IS NULL)
        OR (bp_excluded_at IS NOT NULL
            AND bp_excluded_reason IS NOT NULL AND btrim(bp_excluded_reason) <> ''
            AND bp_excluded_by_name IS NOT NULL AND btrim(bp_excluded_by_name) <> '')
    );
