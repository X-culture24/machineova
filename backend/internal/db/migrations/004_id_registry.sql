-- National ID registry (NRB extracts). Identity reference used when an ID is not on the
-- voter register: lookup can still confirm who the person is and where they are registered
-- administratively. Loaded by cmd/import-idregistry; read-only to the API.
--
-- national_id is digits only with leading zeros removed (see api.registryKey).
-- Only the fields lookup needs are stored; parents' names, tribe, clan and family are not.
CREATE TABLE id_registry (
    national_id  TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    sex          CHAR(1) CHECK (sex IN ('F', 'M')),
    dob          DATE,
    county       TEXT,
    sub_county   TEXT,
    division     TEXT,
    location     TEXT,
    sub_location TEXT,
    village      TEXT,
    source       TEXT NOT NULL
);
