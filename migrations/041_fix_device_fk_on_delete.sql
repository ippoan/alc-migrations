-- devices 削除時に FK 制約違反で 500 エラーになる問題を修正

-- device_registration_requests.device_id → ON DELETE SET NULL
ALTER TABLE alc_api.device_registration_requests
    DROP CONSTRAINT device_registration_requests_device_id_fkey;
ALTER TABLE alc_api.device_registration_requests
    ADD CONSTRAINT device_registration_requests_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES alc_api.devices(id)
    ON DELETE SET NULL;

-- time_punches.device_id → ON DELETE SET NULL
ALTER TABLE alc_api.time_punches
    DROP CONSTRAINT time_punches_device_id_fkey;
ALTER TABLE alc_api.time_punches
    ADD CONSTRAINT time_punches_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES alc_api.devices(id)
    ON DELETE SET NULL;
