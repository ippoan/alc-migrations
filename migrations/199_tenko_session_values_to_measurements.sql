-- 点呼セッションの値の写し (アルコール・体温・血圧) を測定 (measurements) へ写す
--
-- 点呼の値の置き場を測定の 1 か所にする (tenko-unify の段階 3)。読む側 (measurements-worker・tenko-worker) は
-- この後、セッションの measurement_id が指す測定から値を読むよう切り替え、最後にセッションの値の列を消す。
-- 段階 2 (alc-measurements-worker v0.1.15) からは、どの点呼でも測定に値が入る。それより前のセッションは
-- 測定が無い (自動・遠隔点呼でアルコールの段より前に閉じたもの) か、測定に体温・血圧が無い。
--
-- * 測定を指すセッション: 測定の空欄だけをセッションの値で埋める。測定に在る値は上書きしない
--   (測定の値を正とする)。同じ測定を指すセッションが複数あれば、値を持つ一番新しいセッションを使う
-- * 測定を指さず値を持つセッション: 測定の行を作って結ぶ。アルコールの結果が在れば completed、
--   無ければ started (段階 2 で開始時に作る測定と同じ)。測定の時刻はアルコールの測定時刻、無ければ
--   体温・血圧の時刻、開始の時刻の順
-- * 食い違い (両方に値が在って違う) と、測定にだけアルコールの結果が在るセッションの件数を NOTICE で出す
-- * セッションの updated_at は変えない (記録の hash の元の値。閉じたセッションは記録が既に在る)
-- * 表の所有者で流すので RLS は効かない (measurements・tenko_sessions は FORCE でない)。dev の軸の行も対象。
--   作る測定の is_dev はセッションの is_dev

SET LOCAL lock_timeout = '10s';

DO $$
DECLARE
    n bigint;
BEGIN
    SELECT count(*) INTO n
      FROM alc_api.tenko_sessions s
      JOIN alc_api.measurements m ON m.tenant_id = s.tenant_id AND m.id = s.measurement_id
     WHERE (s.alcohol_result IS NOT NULL AND m.result IS NOT NULL AND s.alcohol_result <> m.result)
        OR (s.alcohol_value IS NOT NULL AND m.alcohol_level IS NOT NULL AND s.alcohol_value <> m.alcohol_level)
        OR (s.alcohol_result IS NOT NULL AND s.alcohol_tested_at IS NOT NULL AND m.result IS NOT NULL
            AND s.alcohol_tested_at <> m.measured_at)
        OR (s.alcohol_face_photo_url IS NOT NULL AND m.face_photo_url IS NOT NULL
            AND s.alcohol_face_photo_url <> m.face_photo_url)
        OR (s.temperature IS NOT NULL AND m.temperature IS NOT NULL AND s.temperature <> m.temperature)
        OR (s.systolic IS NOT NULL AND m.systolic IS NOT NULL AND s.systolic <> m.systolic)
        OR (s.diastolic IS NOT NULL AND m.diastolic IS NOT NULL AND s.diastolic <> m.diastolic)
        OR (s.pulse IS NOT NULL AND m.pulse IS NOT NULL AND s.pulse <> m.pulse)
        OR (s.medical_measured_at IS NOT NULL AND m.medical_measured_at IS NOT NULL
            AND s.medical_measured_at <> m.medical_measured_at)
        OR (s.medical_manual_input IS NOT NULL AND m.medical_manual_input IS NOT NULL
            AND s.medical_manual_input <> m.medical_manual_input);
    RAISE NOTICE '199: 測定と値が食い違うセッション (測定の値のまま): %', n;

    SELECT count(*) INTO n
      FROM alc_api.tenko_sessions s
      JOIN alc_api.measurements m ON m.tenant_id = s.tenant_id AND m.id = s.measurement_id
     WHERE s.alcohol_result IS NULL AND m.result IS NOT NULL;
    RAISE NOTICE '199: 測定にだけアルコールの結果が在るセッション: %', n;

    SELECT count(*) INTO n
      FROM (SELECT 1
              FROM alc_api.tenko_sessions
             WHERE measurement_id IS NOT NULL
               AND (alcohol_result IS NOT NULL OR temperature IS NOT NULL OR systolic IS NOT NULL)
             GROUP BY tenant_id, measurement_id
            HAVING count(*) > 1) d;
    RAISE NOTICE '199: 値を持つセッションが 2 つ以上指す測定 (一番新しいセッションの値で埋める): %', n;
END $$;

-- 測定を指すセッション: 測定の空欄を埋める
UPDATE alc_api.measurements m
   SET result = COALESCE(m.result, s.alcohol_result),
       alcohol_level = COALESCE(m.alcohol_level, s.alcohol_value),
       measured_at = CASE WHEN m.result IS NULL AND s.alcohol_result IS NOT NULL
                          THEN COALESCE(s.alcohol_tested_at, m.measured_at)
                          ELSE m.measured_at END,
       face_photo_url = COALESCE(m.face_photo_url, s.alcohol_face_photo_url),
       temperature = COALESCE(m.temperature, s.temperature),
       systolic = COALESCE(m.systolic, s.systolic),
       diastolic = COALESCE(m.diastolic, s.diastolic),
       pulse = COALESCE(m.pulse, s.pulse),
       medical_measured_at = COALESCE(m.medical_measured_at, s.medical_measured_at),
       medical_manual_input = COALESCE(m.medical_manual_input, s.medical_manual_input),
       updated_at = NOW()
  FROM (SELECT DISTINCT ON (tenant_id, measurement_id) *
          FROM alc_api.tenko_sessions
         WHERE measurement_id IS NOT NULL
           AND (alcohol_result IS NOT NULL OR alcohol_value IS NOT NULL OR alcohol_face_photo_url IS NOT NULL
                OR temperature IS NOT NULL OR systolic IS NOT NULL OR diastolic IS NOT NULL
                OR pulse IS NOT NULL OR medical_measured_at IS NOT NULL OR medical_manual_input IS NOT NULL)
         ORDER BY tenant_id, measurement_id, created_at DESC, id DESC) s
 WHERE m.tenant_id = s.tenant_id
   AND m.id = s.measurement_id
   AND ((m.result IS NULL AND s.alcohol_result IS NOT NULL)
        OR (m.alcohol_level IS NULL AND s.alcohol_value IS NOT NULL)
        OR (m.face_photo_url IS NULL AND s.alcohol_face_photo_url IS NOT NULL)
        OR (m.temperature IS NULL AND s.temperature IS NOT NULL)
        OR (m.systolic IS NULL AND s.systolic IS NOT NULL)
        OR (m.diastolic IS NULL AND s.diastolic IS NOT NULL)
        OR (m.pulse IS NULL AND s.pulse IS NOT NULL)
        OR (m.medical_measured_at IS NULL AND s.medical_measured_at IS NOT NULL)
        OR (m.medical_manual_input IS NULL AND s.medical_manual_input IS NOT NULL));

-- 測定を指さず値を持つセッション: 測定を作って結ぶ (src は 2 回読むので 1 回だけ評価され、id が揃う)
WITH src AS MATERIALIZED (
    SELECT s.*, gen_random_uuid() AS new_measurement_id
      FROM alc_api.tenko_sessions s
     WHERE s.measurement_id IS NULL
       AND (s.alcohol_result IS NOT NULL OR s.alcohol_value IS NOT NULL OR s.alcohol_face_photo_url IS NOT NULL
            OR s.temperature IS NOT NULL OR s.systolic IS NOT NULL OR s.diastolic IS NOT NULL
            OR s.pulse IS NOT NULL OR s.medical_measured_at IS NOT NULL OR s.medical_manual_input IS NOT NULL)
),
ins AS (
    INSERT INTO alc_api.measurements (
        id, tenant_id, employee_id, alcohol_level, result, face_photo_url, measured_at,
        temperature, systolic, diastolic, pulse, medical_measured_at, medical_manual_input,
        status, is_dev, created_at, updated_at
    )
    SELECT new_measurement_id, tenant_id, employee_id, alcohol_value, alcohol_result, alcohol_face_photo_url,
           COALESCE(alcohol_tested_at, medical_measured_at, started_at, created_at),
           temperature, systolic, diastolic, pulse, medical_measured_at, medical_manual_input,
           CASE WHEN alcohol_result IS NOT NULL THEN 'completed' ELSE 'started' END, is_dev, created_at, NOW()
      FROM src
    RETURNING id
)
UPDATE alc_api.tenko_sessions s
   SET measurement_id = src.new_measurement_id
  FROM src
 WHERE s.tenant_id = src.tenant_id
   AND s.id = src.id
   AND EXISTS (SELECT 1 FROM ins WHERE ins.id = src.new_measurement_id);
