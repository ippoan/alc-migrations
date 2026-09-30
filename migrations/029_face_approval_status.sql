-- 顔登録の承認ワークフロー
ALTER TABLE employees
  ADD COLUMN face_approval_status TEXT NOT NULL DEFAULT 'none',
  ADD COLUMN face_approved_by UUID,
  ADD COLUMN face_approved_at TIMESTAMPTZ;

-- 既存の顔登録済み従業員は approved に設定
UPDATE employees
SET face_approval_status = 'approved',
    face_approved_at = face_embedding_at
WHERE face_embedding IS NOT NULL;

ALTER TABLE employees
  ADD CONSTRAINT chk_face_approval_status
  CHECK (face_approval_status IN ('none', 'pending', 'approved', 'rejected'));
