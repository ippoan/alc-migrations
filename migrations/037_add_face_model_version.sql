-- Add face_model_version to track which model/normalization was used for embedding
ALTER TABLE employees ADD COLUMN IF NOT EXISTS face_model_version TEXT;
