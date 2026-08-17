// daemon.log is the only forensic trail for incidents hours old; a line
// without a time is undiagnosable. The launcher redirects the daemon's
// stderr there, so every module logs through this one function.
export function logLine(message: string): void {
  console.error(`${new Date().toISOString()} ${message}`);
}
