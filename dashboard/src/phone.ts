/** Kenyan mobile numbers: exactly 10 digits starting 07 or 01. +254 / 254
 *  forms are accepted and returned as 07…/01…; spaces, dashes, dots and
 *  brackets are ignored. null means "not a valid number". The API applies
 *  the same rule. */
export function kenyanMobile(input: string): string | null {
  const s = input.trim();
  if (!/^\+?[0-9 ().-]+$/.test(s)) return null;
  let n = s.replace(/[^0-9]/g, "");
  if (n.length === 12 && n.startsWith("254")) n = "0" + n.slice(3);
  return n.length === 10 && /^0[17]/.test(n) ? n : null;
}

export const phoneHint = "Enter a 10-digit phone number, for example 0712 345 678";

/** Message for an optional phone field: null when empty or valid. */
export function phoneProblem(input: string): string | null {
  return input.trim() === "" || kenyanMobile(input) ? null : phoneHint;
}

/** How many of the 10 digits are typed so far (+254 counts as the leading 0). */
export function phoneDigitCount(input: string): number {
  let n = input.replace(/[^0-9]/g, "");
  if (n.startsWith("254") && /^\s*\+?254/.test(input)) n = "0" + n.slice(3);
  return n.length;
}
