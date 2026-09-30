-- role を TEXT から TEXT[] に変更 (複数ロール対応)

-- 1. DEFAULT を先に削除
ALTER TABLE employees ALTER COLUMN role DROP DEFAULT;

-- 2. 旧 CHECK 制約を先に削除 (型変換前に必須)
ALTER TABLE employees DROP CONSTRAINT IF EXISTS employees_role_check;

-- 3. 型変換 (既存の単一ロール値を配列に変換)
ALTER TABLE employees
  ALTER COLUMN role TYPE TEXT[] USING ARRAY[role]::TEXT[];

-- 4. 新しい DEFAULT を設定
ALTER TABLE employees
  ALTER COLUMN role SET DEFAULT ARRAY['driver']::TEXT[];

-- 5. 新 CHECK 制約 (配列の全要素が有効値であること)
ALTER TABLE employees ADD CONSTRAINT employees_role_check
  CHECK (role <@ ARRAY['driver', 'manager', 'admin']::TEXT[]);
