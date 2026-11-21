-- A check-in is never refused for missing details: the person is present, so they are recorded.
-- The register may lack a name or sex, and people not on it often can't give their constituency
-- and ward on the spot. Sex may now be unknown (NULL); name and area may be blank (''), and a
-- person with no known area in the event's county is recorded out of region.
ALTER TABLE checkins ALTER COLUMN sex DROP NOT NULL;
