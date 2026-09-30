-- 社員番号 (code) カラム追加、nfc_id を optional に変更
ALTER TABLE employees ADD COLUMN code TEXT;
ALTER TABLE employees ALTER COLUMN nfc_id DROP NOT NULL;

-- code のユニーク制約 (tenant 内で一意)
CREATE UNIQUE INDEX idx_employees_code ON employees(tenant_id, code) WHERE code IS NOT NULL;

-- nfc_id のユニーク制約を維持 (NULL は許容)
-- 既存の UNIQUE (tenant_id, nfc_id) は NULL を複数許容するので変更不要
