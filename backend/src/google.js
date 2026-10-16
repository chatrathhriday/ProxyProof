// "Sign in with Google", restricted to the college's Google Workspace domain.
//
// The app gets an ID token (a JWT signed by Google) and sends it here. We check:
//   - signature against Google's published public keys (JWKS, cached)
//   - iss = Google, aud = our OAuth client id, not expired
//   - email_verified and hd (hosted domain) = vitstudent.ac.in (students) or vit.ac.in (faculty)
// "hd" is set by Google only for Workspace accounts of that domain, so a personal Gmail
// with a look-alike name can't pass. No password is ever stored for these students.
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';

export const GOOGLE_CLIENT_ID =
  process.env.GOOGLE_CLIENT_ID || '37429262055-7u3mm2sj9takv871no63dpeikab9rj4m.apps.googleusercontent.com';
export const STUDENT_DOMAIN = (process.env.STUDENT_DOMAIN || 'vitstudent.ac.in').toLowerCase();
export const FACULTY_DOMAIN = (process.env.FACULTY_DOMAIN || 'vit.ac.in').toLowerCase();

const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
let keys = { at: 0, byKid: new Map() };

let resolveKey = googleKey;
/** Tests sign their own tokens; this swaps in their public key. */
export const setGoogleKeyResolverForTests = (fn) => {
  resolveKey = fn;
};

async function googleKey(kid) {
  if (!keys.byKid.has(kid) || Date.now() - keys.at > 3600_000) {
    const res = await fetch(JWKS_URL);
    if (!res.ok) throw new Error('could not fetch Google keys');
    const { keys: list } = await res.json();
    keys = { at: Date.now(), byKid: new Map(list.map((k) => [k.kid, crypto.createPublicKey({ key: k, format: 'jwk' })])) };
  }
  const key = keys.byKid.get(kid);
  if (!key) throw new Error('unknown Google key id');
  return key;
}

/** Returns { email, name, domain } for a valid college account, or throws with a user-facing message. */
export async function verifyGoogleIdToken(idToken) {
  const decoded = jwt.decode(idToken, { complete: true });
  if (!decoded?.header?.kid) throw new Error('invalid Google token');
  const payload = jwt.verify(idToken, await resolveKey(decoded.header.kid), {
    algorithms: ['RS256'],
    audience: GOOGLE_CLIENT_ID,
    issuer: ['accounts.google.com', 'https://accounts.google.com'],
  });
  const email = String(payload.email || '').toLowerCase();
  if (!payload.email_verified) throw new Error('Google email not verified');
  const domain = [STUDENT_DOMAIN, FACULTY_DOMAIN].find((d) => payload.hd === d && email.endsWith(`@${d}`));
  if (!domain) throw new Error(`Use your @${STUDENT_DOMAIN} (students) or @${FACULTY_DOMAIN} (faculty) Google account`);
  return { email, name: payload.name || email.split('@')[0], domain };
}
