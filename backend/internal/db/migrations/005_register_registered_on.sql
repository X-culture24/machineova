-- Date the voter registered (from the IEBC / SDICS register), shown with registration status.
ALTER TABLE register_voters ADD COLUMN registered_on DATE;
