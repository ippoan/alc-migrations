-- Mark tickets whose person_name is an external party (not in employee master).
-- When true, the UI should render person_name as free-text input and skip the
-- "unlinked employee" warning/auto-linking flow.
ALTER TABLE alc_api.trouble_tickets
    ADD COLUMN person_is_external BOOLEAN NOT NULL DEFAULT FALSE;
