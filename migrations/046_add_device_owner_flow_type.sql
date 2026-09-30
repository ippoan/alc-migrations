-- Add 'device_owner' to flow_type check constraint
ALTER TABLE device_registration_requests DROP CONSTRAINT device_registration_requests_flow_type_check;
ALTER TABLE device_registration_requests ADD CONSTRAINT device_registration_requests_flow_type_check
    CHECK (flow_type IN ('qr_temp', 'qr_permanent', 'url', 'device_owner'));
