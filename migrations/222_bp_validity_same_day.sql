-- 血圧の有効時間を体温から切り離し、既定を「当日中 (日本時間)」にする (足すだけ。Refs ippoan/alc-app#676)
--
-- 体温は点呼のたびにキオスクで測るので、有効時間は今のまま measurement_validity_minutes (分) を使う。血圧は測定台で
-- 測り、点呼はその日の血圧を使う (国交省 FAQ: 測定値の有効時間に制限は設けていない)。
--
-- 1. employee_health_baselines.bp_validity_minutes: 血圧の有効時間 (分)。NULL = 当日中 (日本時間の同じ日付)。
--    既存の行も基準値の無い社員も当日中になる (既存の行は書き換えない)。測定台の「有効時間内に 2 回まで」も同じ規則で数える。
-- 2. measurements.bp_measured_at: 血圧を測った時刻。これまで点呼の測定は medical_measured_at 1 つに体温と血圧の早い方を
--    入れていたので、体温と血圧を別々の時刻で有効時間に照らせなかった。以後 medical_measured_at は体温 (測定台では血圧) の
--    時刻、bp_measured_at は血圧の時刻。既存の行は NULL のままで、読む側が COALESCE(bp_measured_at, medical_measured_at,
--    measured_at) で今の値へ落とす。
--
-- どちらも NULL 可・DEFAULT なし (既存行と既存の INSERT / UPDATE を壊さない)。表の権限・RLS は変えない。
ALTER TABLE alc_api.employee_health_baselines
    ADD COLUMN bp_validity_minutes INTEGER NULL
        CONSTRAINT employee_health_baselines_bp_validity_minutes_check CHECK (bp_validity_minutes IS NULL OR bp_validity_minutes > 0);

ALTER TABLE alc_api.measurements
    ADD COLUMN bp_measured_at TIMESTAMPTZ NULL;
