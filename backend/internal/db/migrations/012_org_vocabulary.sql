-- The words an organization's dashboard and field app use. 'standard' is the campaign wording
-- (voters, mobilize, check in); 'sdics_chiefs' is for training chiefs on the SDICS app
-- (chiefs, onboard, mark chief present). Only labels change, plus onboarding requires a phone
-- number; the data model (events, drives, mobilizations) is the same.
ALTER TABLE organizations
    ADD COLUMN vocabulary TEXT NOT NULL DEFAULT 'standard'
        CHECK (vocabulary IN ('standard', 'sdics_chiefs'));
