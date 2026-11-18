// SDICS look: Lexend, SDICS green / navy / amber and the Kenyan flag stripe, as in the SDICS
// dashboard and apps. On when the dashboard is served from *.sdics.tech (so the sign-in page
// already looks like SDICS) or the signed-in organization is the SDICS chiefs training.
// Everyone else keeps the MachineNova look.

export const sdicsHost = (): boolean => /(^|\.)sdics\.tech$/i.test(window.location.hostname);

const FAVICON = {
  sdics:
    "data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22%3E%3Crect width=%2232%22 height=%2232%22 rx=%228%22 fill=%22%230f1419%22/%3E%3Crect y=%2226%22 width=%2232%22 height=%222%22 fill=%22%23bb0000%22/%3E%3Crect y=%2228%22 width=%2232%22 height=%224%22 fill=%22%23006600%22/%3E%3Cpath d=%22M9 14.5l4.5 4.5L23 9.5%22 stroke=%22%2300d084%22 stroke-width=%223.2%22 fill=%22none%22 stroke-linecap=%22round%22/%3E%3C/svg%3E",
  standard:
    "data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22%3E%3Crect width=%2232%22 height=%2232%22 rx=%228%22 fill=%22%230f8a7a%22/%3E%3Cpath d=%22M9 16.5l4.5 4.5L23 11.5%22 stroke=%22white%22 stroke-width=%223%22 fill=%22none%22 stroke-linecap=%22round%22/%3E%3C/svg%3E",
};

/** Switches the page between the SDICS and the standard look (tokens in styles.css). */
export function applyBrand(sdics: boolean) {
  const root = document.documentElement;
  if (sdics) root.dataset.brand = "sdics";
  else delete root.dataset.brand;
  document.title = sdics ? "SDICS Checkin" : "Checkin";
  const icon = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (icon) icon.href = sdics ? FAVICON.sdics : FAVICON.standard;
}

export const isSdicsBrand = (): boolean => document.documentElement.dataset.brand === "sdics";
