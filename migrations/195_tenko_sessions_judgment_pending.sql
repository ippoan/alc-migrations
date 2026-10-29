-- 点呼セッションの状態に「判定待ち」(judgment_pending) を足す (expand。Refs ippoan/rust-alc-api#680)。
--
-- 点呼の記録の入口を測定の口 (ippoan/alc-measurements-worker) に一本化するのに合わせ、遠隔点呼・IT点呼は
-- 乗務員の側が終わった時点では completed にせず judgment_pending にし、運行管理者の判定で閉じて
-- 点呼の記録 (tenko_records、作成後は UPDATE / DELETE 不可) を書く。記録の record_data はセッションの JSON なので、
-- 判定が記録の hash に入る。
--
-- 値を 1 つ足すだけで、既存の値は外さない (いまの書き手はこの値を書かないので、既存の行で張れなくなることは無い)。
-- DROP に IF EXISTS を付けない: 名前が違っていたら黙って旧い制約を残さず、ここで落とす。
ALTER TABLE alc_api.tenko_sessions DROP CONSTRAINT tenko_sessions_status_check;
ALTER TABLE alc_api.tenko_sessions ADD CONSTRAINT tenko_sessions_status_check
    CHECK (status IN (
        'identity_verified',
        'alcohol_testing',
        'medical_pending',
        'self_declaration_pending',
        'daily_inspection_pending',
        'carrying_items_pending',
        'instruction_pending',
        'report_pending',
        'judgment_pending',
        'completed',
        'cancelled',
        'interrupted'
    ));
