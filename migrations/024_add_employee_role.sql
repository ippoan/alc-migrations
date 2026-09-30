-- 従業員ロール (driver=運行者, manager=運行管理者, admin=システム管理者)
ALTER TABLE employees ADD COLUMN role TEXT NOT NULL DEFAULT 'driver'
  CHECK (role IN ('driver', 'manager', 'admin'));
