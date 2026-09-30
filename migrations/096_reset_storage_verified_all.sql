-- Reset ALL storage_verified to NULL for re-verification.
-- Previous verification used a buggy exists() that ignored HTTP status codes,
-- so some files were incorrectly marked as verified.
-- This runs as SECURITY DEFINER function to bypass RLS.
CREATE OR REPLACE FUNCTION reset_storage_verified_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = alc_api
AS $$
BEGIN
    UPDATE files SET storage_verified = NULL;
END;
$$;

SELECT reset_storage_verified_all();
DROP FUNCTION reset_storage_verified_all();
