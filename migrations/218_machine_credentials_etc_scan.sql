-- Refs ohishi-exp/nuxt-dtako-admin#1287。複合機の ETC コーポレートカード発行明細書スキャン用の purpose。
-- 機械用資格情報の purpose に 'etc-scan' を許す。216 の CHECK (machine_credentials_purpose_check) を同じ名前で作り直す (足すだけ)。

ALTER TABLE alc_api.machine_credentials
    DROP CONSTRAINT machine_credentials_purpose_check,
    ADD CONSTRAINT machine_credentials_purpose_check CHECK (purpose IN ('leave-scan', 'fuel-utran', 'etc-scan'));
