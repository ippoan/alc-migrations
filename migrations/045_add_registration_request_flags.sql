-- Add device owner / developer flags to registration requests for propagation to devices
ALTER TABLE device_registration_requests ADD COLUMN is_device_owner BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE device_registration_requests ADD COLUMN is_dev_device BOOLEAN NOT NULL DEFAULT false;
