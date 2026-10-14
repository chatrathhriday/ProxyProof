// Single source of "now" for time-based rules (tokens, spot-check deadlines, coverage).
// Tests move it forward instead of sleeping for 20 s.
let offsetMs = 0;

export const now = () => Date.now() + offsetMs;
export const advance = (ms) => {
  offsetMs += ms;
};
export const resetClock = () => {
  offsetMs = 0;
};
