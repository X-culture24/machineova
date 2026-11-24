ALTER TABLE events ADD COLUMN polling_station_code text;
ALTER TABLE events ADD COLUMN coverage_level text CHECK (coverage_level IN ('national', 'county', 'constituency', 'ward'));

CREATE TABLE sdics_station_roll (
    code text PRIMARY KEY,
    name text NOT NULL,
    county text NOT NULL,
    constituency text NOT NULL,
    ward text NOT NULL,
    registered_voters integer NOT NULL CHECK (registered_voters >= 0)
);
