-- 点呼セッションの値の列 (測定の写し) を消す (tenko-unify 段階 3 の最後)
--
-- 値 (アルコール・体温・血圧) の置き場は測定 (measurements) の 1 か所になった。セッションは measurement_id で
-- 測定を指し、読む側 (alc-measurements-worker のセッションの応答・alc-tenko-worker の日々の健康状態と乗務員情報) は
-- 測定から読む。書く側も写すのをやめた。古いセッションの値は 199 で測定へ写してある。
--
-- * 消すのはセッションの 10 列だけ。点呼記録 (tenko_records) の同名の列と record_data は法定の控えなので残す
-- * 列に掛かる index・view・trigger・関数は無い
-- * contract (DROP COLUMN) なので merge では流れない。全 worker が移った後に workflow_dispatch (allow_contract) で流す

SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.tenko_sessions
    DROP COLUMN alcohol_result,
    DROP COLUMN alcohol_value,
    DROP COLUMN alcohol_tested_at,
    DROP COLUMN alcohol_face_photo_url,
    DROP COLUMN temperature,
    DROP COLUMN systolic,
    DROP COLUMN diastolic,
    DROP COLUMN pulse,
    DROP COLUMN medical_measured_at,
    DROP COLUMN medical_manual_input;
