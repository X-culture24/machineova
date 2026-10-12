-- Some registered voters in the IEBC/SDICS export carry only their ID and electoral area
-- (no name/sex/DOB). They are still registered, so keep them; lookup fills identity from
-- id_registry when it can.
ALTER TABLE register_voters ALTER COLUMN name DROP NOT NULL;
ALTER TABLE register_voters ALTER COLUMN sex DROP NOT NULL;
ALTER TABLE register_voters ALTER COLUMN dob DROP NOT NULL;
