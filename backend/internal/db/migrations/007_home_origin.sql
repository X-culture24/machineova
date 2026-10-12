-- Where a person comes from, per their national ID record (NRB), captured server-side at
-- check-in / mobilization so out-of-area people are reported from records, not from what
-- they tell the agent.
ALTER TABLE checkins
    ADD COLUMN home_county       TEXT,
    ADD COLUMN home_sub_county   TEXT,
    ADD COLUMN home_location     TEXT,
    ADD COLUMN home_sub_location TEXT,
    ADD COLUMN home_village      TEXT;

ALTER TABLE mobilizations
    ADD COLUMN in_region         BOOLEAN,
    ADD COLUMN home_county       TEXT,
    ADD COLUMN home_sub_county   TEXT,
    ADD COLUMN home_location     TEXT,
    ADD COLUMN home_sub_location TEXT,
    ADD COLUMN home_village      TEXT;
