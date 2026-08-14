import { homedir } from "node:os";
import { join } from "node:path";

// One XDG state base for every rail module — acks, hints, page state,
// pokemon mapping, and the generated theme files all hang off this.
export const XDG_STATE =
  process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state");
