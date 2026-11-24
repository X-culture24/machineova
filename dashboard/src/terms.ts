// The words the dashboard uses, per organization. Campaigns say voters, mobilization and check-in;
// SDICS calls its participants members and tracks onboarding alongside check-ins.
import { useAuth } from "./auth";

const standard = {
  chiefs: false,
  mobilization: "Mobilization",
  mobilizationTab: "Mobilize",
  mobilizationSubtitle: "Voters your field teams register during outreach, by region.",
  mobilized: "Mobilized",
  peopleMobilized: "Voters mobilized",
  mobilizedToday: "Mobilized today",
  mobilizedBy: "Mobilized by",
  newDrive: "+ New drive",
  drive: "Drive",
  driveColumn: "Region / drive",
  noDrives: "No mobilization drives yet.",
  activeRegions: "Active regions",
  registeredList: "Registered voters",
  noneRegistered: "No voters registered yet.",
  targetPeople: "Target voters",
  topMobilizers: "Top mobilizers",
  assignMobilizers: "Assign mobilizers",
  topRegions: "Top regions by mobilization",
  homeSubtitle: "Here's how mobilization and check-in are tracking.",
  events: "Events",
  totalEvents: "Total events",
  recentEvents: "Recent events",
  checkin: "Check-in",
  checkins: "Check-ins",
  checkInPeople: "Check in voters",
  peopleSubtitle: "Everyone checked in at events and mobilized in the field.",
  event: "Event",
};

export type Terms = typeof standard;

const sdicsChiefs: Terms = {
  chiefs: true,
  mobilization: "Onboarding",
  mobilizationTab: "Onboard",
  mobilizationSubtitle: "Members onboarded in each county, with the phone numbers collected. Look-ups use the IEBC voter register.",
  mobilized: "Onboarded",
  peopleMobilized: "Members onboarded",
  mobilizedToday: "Onboarded today",
  mobilizedBy: "Onboarded by",
  newDrive: "+ New county",
  drive: "County",
  driveColumn: "County",
  noDrives: "No counties set up for onboarding yet.",
  activeRegions: "Active counties",
  registeredList: "Members onboarded",
  noneRegistered: "No members onboarded yet.",
  targetPeople: "Target members",
  topMobilizers: "Top operators",
  assignMobilizers: "Assign trainers",
  topRegions: "Onboarding by county",
  homeSubtitle: "Attendance and onboarding across your events.",
  events: "Events",
  totalEvents: "Total events",
  recentEvents: "Recent events",
  checkin: "Check in member",
  checkins: "Members checked in",
  checkInPeople: "Check in member",
  peopleSubtitle: "Search and export event attendance.",
  event: "Event",
};

export function useTerms(): Terms {
  const { me } = useAuth();
  return me?.organization?.vocabulary === "sdics_chiefs" ? sdicsChiefs : standard;
}
