-- Candidates' regions become full keys: ward and constituency names repeat between counties
-- (there is a "Township" ward in several), so a bare name could put a candidate on the wrong
-- ballot in a nationwide election. Keys: "County / Constituency" and "County / Constituency / Ward".
-- Bare names are rewritten where they are unambiguous within their election; county races keep
-- the county name, which is already unique.
WITH keyed AS (
    SELECT c.id,
           min(CASE p.level WHEN 'constituency' THEN s.county || ' / ' || s.constituency
                            ELSE s.county || ' / ' || s.constituency || ' / ' || s.ward END) AS key,
           count(DISTINCT CASE p.level WHEN 'constituency' THEN s.county || ' / ' || s.constituency
                                       ELSE s.county || ' / ' || s.constituency || ' / ' || s.ward END) AS n
    FROM candidates c
    JOIN positions p ON p.id = c.position_id AND p.level IN ('constituency', 'ward')
    JOIN election_stations es ON es.election_id = p.election_id
    JOIN polling_stations s ON s.code = es.station_code
    WHERE c.region NOT LIKE '% / %'
      AND lower(c.region) = lower(CASE p.level WHEN 'constituency' THEN s.constituency ELSE s.ward END)
    GROUP BY c.id
)
UPDATE candidates c SET region = k.key FROM keyed k WHERE k.id = c.id AND k.n = 1;
