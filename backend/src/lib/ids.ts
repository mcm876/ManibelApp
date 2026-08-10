/**
 * Same CM-/DR- style IDs the client generated locally
 * (UserSession._generateCommuterId / DriverSession._generateDriverId), but
 * backed by random digits instead of a timestamp so concurrent signups
 * on the server can't collide.
 */
function randomDigits(length: number): string {
  let out = '';
  for (let i = 0; i < length; i++) out += Math.floor(Math.random() * 10);
  return out;
}

export const generateCommuterId = () => `CM-${randomDigits(5)}`;
export const generateDriverId = () => `DR-${randomDigits(5)}`;
export const generatePlateNumber = () => `NGP-${randomDigits(4)}`;
