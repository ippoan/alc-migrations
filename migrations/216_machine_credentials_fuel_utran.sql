-- Refs yhonda-ohishi/nginx#814。USB アップローダー (fuel-usb-uploader) 用の purpose。
-- 機械用資格情報の purpose に 'fuel-utran' を許す。173 で名前を付けずに作った CHECK
-- (自動の名前 machine_credentials_purpose_check) を、同じ名前で作り直す (足すだけ。既存の行はすべて 'leave-scan')。

ALTER TABLE alc_api.machine_credentials
    DROP CONSTRAINT machine_credentials_purpose_check,
    ADD CONSTRAINT machine_credentials_purpose_check CHECK (purpose IN ('leave-scan', 'fuel-utran'));
