-- App version tracking for OTA updates
ALTER TABLE devices ADD COLUMN app_version_code INTEGER;
ALTER TABLE devices ADD COLUMN app_version_name TEXT;
ALTER TABLE devices ADD COLUMN app_version_reported_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN is_device_owner BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE devices ADD COLUMN is_dev_device BOOLEAN NOT NULL DEFAULT false;
