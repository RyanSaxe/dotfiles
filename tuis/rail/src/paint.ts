// Paint scheduling: the rail someone is LOOKING at repaints before the
// seventy-nine they can't see. A refresh awaits only the visible panes
// (active window of a session with a real client — milliseconds), then
// queues the rest as a background fill in likely-to-jump order. The fill
// is latest-frame-wins per pane: a newer refresh's frame replaces a
// queued one instead of writing both, so churny periods coalesce
// off-screen work instead of stacking it. Writes are per-pane
// single-flight — two writers can never interleave on one tty.

export interface PaintTarget {
  paneId: string;
  tty: string;
  frame: string;
}

export interface PaintScheduler {
  // Write these now, concurrently; resolves when every visible pane
  // settled (wall-time ~= the slowest single pane, not the sum).
  paintVisible(targets: PaintTarget[]): Promise<void>;
  // Queue these for the background drain, replacing any queued frame for
  // the same pane. Order is the caller's priority order.
  fill(targets: PaintTarget[]): void;
  // Panes whose queued fill has not landed yet (tests + telemetry).
  pendingCount(): number;
}

export interface PaintSchedulerOptions {
  write: (tty: string, payload: string) => Promise<boolean>;
  // Called with the result of every completed write, so the caller can
  // maintain its frame diff cache (`pushed`) in one place.
  onResult: (paneId: string, frame: string, ok: boolean) => void;
  // Background writes in flight at once. Small: the point is overlapping
  // drain pauses, not saturating the tmux server's parse loop.
  fillConcurrency?: number;
}

export function makePaintScheduler(
  options: PaintSchedulerOptions,
): PaintScheduler {
  const concurrency = options.fillConcurrency ?? 8;
  // Per-pane write chain: appending through this map is what guarantees
  // one writer per tty at a time, across visible paints and fills alike.
  const inFlight = new Map<string, Promise<void>>();
  // The background queue. Insertion order is priority order; a re-queued
  // pane keeps its newest frame but its original position.
  const queue = new Map<string, PaintTarget>();
  let draining = 0;

  function chain(target: PaintTarget): Promise<void> {
    const previous = inFlight.get(target.paneId) ?? Promise.resolve();
    const next = previous
      .then(() => options.write(target.tty, target.frame))
      .then((ok) => options.onResult(target.paneId, target.frame, ok))
      .catch(() => options.onResult(target.paneId, target.frame, false))
      .finally(() => {
        if (inFlight.get(target.paneId) === next) {
          inFlight.delete(target.paneId);
        }
      });
    inFlight.set(target.paneId, next);
    return next;
  }

  function drain(): void {
    while (draining < concurrency && queue.size > 0) {
      const [paneId, target] = queue.entries().next().value as [
        string,
        PaintTarget,
      ];
      queue.delete(paneId);
      draining += 1;
      void chain(target).finally(() => {
        draining -= 1;
        drain();
      });
    }
  }

  return {
    paintVisible(targets: PaintTarget[]): Promise<void> {
      // A visible paint supersedes any queued fill for the same pane.
      for (const target of targets) queue.delete(target.paneId);
      return Promise.all(targets.map(chain)).then(() => {});
    },
    fill(targets: PaintTarget[]): void {
      for (const target of targets) queue.set(target.paneId, target);
      drain();
    },
    pendingCount: () => queue.size + draining,
  };
}

// Likely-to-jump order for the background fill: the rest of the sessions
// people are attached to first (alt+N targets), then everything else.
// Within a group, window order — matching the number chips.
export function fillOrder<T extends { sessionAttached: boolean }>(
  targets: T[],
): T[] {
  const attached: T[] = [];
  const rest: T[] = [];
  for (const target of targets) {
    (target.sessionAttached ? attached : rest).push(target);
  }
  return [...attached, ...rest];
}
