-- Add optional medical data fields (BLE Medical Gateway: thermometer + blood pressure)
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS temperature DOUBLE PRECISION;
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS systolic INTEGER;
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS diastolic INTEGER;
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS pulse INTEGER;
ALTER TABLE measurements ADD COLUMN IF NOT EXISTS medical_measured_at TIMESTAMPTZ;
