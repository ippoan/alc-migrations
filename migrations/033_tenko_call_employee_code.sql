-- tenko_call_drivers に社員番号カラムを追加 (employees.code とマッチ用)
ALTER TABLE tenko_call_drivers ADD COLUMN IF NOT EXISTS employee_code TEXT;
