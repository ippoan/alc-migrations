-- 最終ログインユーザー情報をデバイスに記録
ALTER TABLE alc_api.devices
  ADD COLUMN last_login_employee_id UUID REFERENCES alc_api.employees(id),
  ADD COLUMN last_login_employee_name TEXT,
  ADD COLUMN last_login_employee_role TEXT[];
