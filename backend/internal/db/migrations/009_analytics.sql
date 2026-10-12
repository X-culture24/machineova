-- Spelling-insensitive place comparison in SQL (matches places.Key in Go).
CREATE FUNCTION place_key(text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN k = 'nairobicity' THEN 'nairobi' ELSE k END
    FROM (SELECT regexp_replace(lower($1), '[^a-z0-9]', '', 'g') AS k) x
$$;
CREATE INDEX polling_stations_county_key ON polling_stations (place_key(county));

-- Registration analysis: adults in the national ID records vs those on the voter register,
-- per home area. Rebuilt by `cmd/build-analytics` after loading either register.
CREATE TABLE registration_stats (
    county     TEXT NOT NULL,
    sub_county TEXT NOT NULL,
    adults     INT NOT NULL,
    registered INT NOT NULL,
    built_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (county, sub_county)
);
