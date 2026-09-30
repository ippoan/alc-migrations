-- Add next_action_detail column to trouble_tasks
ALTER TABLE trouble_tasks ADD COLUMN IF NOT EXISTS next_action_detail text NOT NULL DEFAULT '';
