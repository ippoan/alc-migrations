-- 乗務員の論理削除対応
ALTER TABLE employees ADD COLUMN deleted_at TIMESTAMPTZ;
