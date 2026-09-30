-- Reset storage_verified to NULL so background verification can check each file.
-- Migration 094 incorrectly set all files to true without actual verification.
UPDATE files SET storage_verified = NULL WHERE storage_verified = true;
