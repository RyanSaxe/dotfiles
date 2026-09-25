// The control-mode client: line parsing survives arbitrary chunking,
// reply blocks correlate FIFO to command() calls, %exit disconnects, the
// reconnect ladder backs off 100ms -> 2s and gives up (onGone) after
// ~10s of sustained server absence, and the snapshot query rides the
// same command path with control clients filtered out of the facts.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  ControlParser,
  startControlClient,
  type ControlChild,
  type ControlClientEvents,
  type ControlEvent,
  type ControlTarget,
} from "../src/control.js";
import { collectSnapshot } from "../src/data.js";

// ----- helpers -----------------------------------------------------------

const flush = (): Promise<void> =>
  new Promise((resolve) => setImmediate(resolve));

class FakeChild implements ControlChild {
  written: string[] = [];
  killed = false;
  private dataListener: ((chunk: string) => void) | null = null;
  private exitListener: (() => void) | null = null;
  write(data: string): void {
    this.written.push(data);
  }
  kill(): void {
    this.killed = true;
  }
  onData(listener: (chunk: string) => void): void {
    this.dataListener = listener;
  }
  onExit(listener: () => void): void {
    this.exitListener = listener;
  }
  emit(chunk: string): void {
    this.dataListener?.(chunk);
  }
  exit(): void {
    this.exitListener?.();
  }
}

interface FakeClock {
  timers: {
    setTimeout(fn: () => void, ms: number): unknown;
    clearTimeout(handle: unknown): void;
  };
  now(): number;
  advance(ms: number): Promise<void>;
  scheduledDelays: number[];
}

function makeClock(): FakeClock {
  let nowMs = 0;
  let nextId = 1;
  const queue: { at: number; fn: () => void; id: number }[] = [];
  const scheduledDelays: number[] = [];
  return {
    timers: {
      setTimeout(fn, ms) {
        const id = nextId++;
        scheduledDelays.push(ms);
        queue.push({ at: nowMs + ms, fn, id });
        return id;
      },
      clearTimeout(handle) {
        const index = queue.findIndex((timer) => timer.id === handle);
        if (index >= 0) queue.splice(index, 1);
      },
    },
    now: () => nowMs,
    async advance(ms: number): Promise<void> {
      const until = nowMs + ms;
      for (;;) {
        await flush();
        queue.sort((a, b) => a.at - b.at || a.id - b.id);
        const next = queue[0];
        if (!next || next.at > until) break;
        nowMs = next.at;
        queue.shift();
        next.fn();
      }
      nowMs = until;
      await flush();
    },
    scheduledDelays,
  };
}

function events(over: Partial<ControlClientEvents> = {}): ControlClientEvents {
  return {
    onNotification: () => {},
    onConnect: () => {},
    onDisconnect: () => {},
    onGone: () => {},
    ...over,
  };
}

const TARGET: ControlTarget = { socketPath: "/tmp/sock", session: "main" };

// Connect a client against one FakeChild and complete the handshake.
async function connected(over: Partial<ControlClientEvents> = {}) {
  const clock = makeClock();
  const child = new FakeChild();
  const client = startControlClient({
    events: events(over),
    findTarget: () => Promise.resolve(TARGET),
    spawnChild: () => child,
    timers: clock.timers,
    now: clock.now,
  });
  await flush();
  child.emit("%begin 1 1 1\n%end 1 1 1\n");
  await flush();
  return { clock, child, client };
}

// ----- parser ------------------------------------------------------------

test("parser separates blocks from notifications across chunk splits", () => {
  const parser = new ControlParser();
  const stream =
    "%begin 100 2 1\nP\x1fmain\x1frow one\nrow two\n%end 100 2 1\n" +
    "%window-add @3\n%session-changed $1 main\n";
  const all: ControlEvent[] = [];
  // One character at a time: the harshest possible chunking.
  for (const char of stream) all.push(...parser.feed(char));
  assert.deepEqual(all, [
    { kind: "block", error: false, output: "P\x1fmain\x1frow one\nrow two" },
    { kind: "notification", name: "%window-add", line: "%window-add @3" },
    {
      kind: "notification",
      name: "%session-changed",
      line: "%session-changed $1 main",
    },
  ]);
});

test("parser handles %error blocks and CRLF line endings", () => {
  const parser = new ControlParser();
  const all = parser.feed(
    "%begin 5 9 1\r\nno such window\r\n%error 5 9 1\r\n%exit\r\n",
  );
  assert.deepEqual(all, [
    { kind: "block", error: true, output: "no such window" },
    { kind: "notification", name: "%exit", line: "%exit" },
  ]);
});

test("parser holds an incomplete line until its newline arrives", () => {
  const parser = new ControlParser();
  assert.deepEqual(parser.feed("%layout-change @1 abc"), []);
  assert.deepEqual(parser.feed("def\n"), [
    {
      kind: "notification",
      name: "%layout-change",
      line: "%layout-change @1 abcdef",
    },
  ]);
});

// ----- client ------------------------------------------------------------

test("the handshake block connects; replies correlate FIFO to commands", async () => {
  let connects = 0;
  const { child, client } = await connected({ onConnect: () => connects++ });
  assert.equal(connects, 1);
  assert.equal(client.connected(), true);

  const first = client.command("list-panes -a -F 'x'");
  const second = client.command("list-clients -F 'y'");
  assert.deepEqual(child.written, [
    "list-panes -a -F 'x'\n",
    "list-clients -F 'y'\n",
  ]);
  child.emit("%begin 2 2 1\npane output\n%end 2 2 1\n");
  child.emit("%begin 3 3 1\nclient output\n%end 3 3 1\n");
  assert.equal(await first, "pane output");
  assert.equal(await second, "client output");
});

test("an %error block rejects exactly its own command", async () => {
  const { child, client } = await connected();
  const bad = client.command("list-panes -t nope");
  const good = client.command("list-clients");
  child.emit("%begin 2 2 1\ncan't find window\n%error 2 2 1\n");
  child.emit("%begin 3 3 1\nok\n%end 3 3 1\n");
  await assert.rejects(bad, /can't find window/);
  assert.equal(await good, "ok");
});

test("unknown notifications pass through without disturbing correlation", async () => {
  const seen: string[] = [];
  const { child, client } = await connected({
    onNotification: (name) => seen.push(name),
  });
  const reply = client.command("list-clients");
  child.emit("%never-heard-of-it x y z\n");
  child.emit("%begin 2 2 1\nstill fine\n%end 2 2 1\n");
  assert.deepEqual(seen, ["%never-heard-of-it"]);
  assert.equal(await reply, "still fine");
});

test("%exit disconnects: pending commands reject, onDisconnect fires once", async () => {
  let disconnects = 0;
  const { child, client } = await connected({
    onDisconnect: () => disconnects++,
  });
  const pending = client.command("list-panes");
  child.emit("%exit\n");
  await assert.rejects(pending, /disconnected/);
  assert.equal(disconnects, 1);
  assert.equal(client.connected(), false);
  assert.equal(child.killed, true);
  // The child's real process exit arriving afterwards is a no-op.
  child.exit();
  assert.equal(disconnects, 1);
  await assert.rejects(client.command("anything"), /not connected/);
});

test("commands reject while disconnected instead of queueing", async () => {
  const clock = makeClock();
  const client = startControlClient({
    events: events(),
    findTarget: () => Promise.reject(new Error("no server running")),
    spawnChild: () => new FakeChild(),
    timers: clock.timers,
    now: clock.now,
  });
  await flush();
  await assert.rejects(client.command("list-panes"), /not connected/);
  client.stop();
});

test("reconnect ladder backs off 100ms->2s, then ~10s of failure is gone", async () => {
  let gone = 0;
  const clock = makeClock();
  const client = startControlClient({
    events: events({ onGone: () => gone++ }),
    findTarget: () => Promise.reject(new Error("no server running")),
    spawnChild: () => new FakeChild(),
    timers: clock.timers,
    now: clock.now,
  });
  await clock.advance(30_000);
  // t=0 fails, then retries at the ladder's spacing; the attempt at
  // t=11100 crosses the 10s line and gives up instead of rescheduling.
  assert.deepEqual(
    clock.scheduledDelays,
    [100, 200, 400, 800, 1600, 2000, 2000, 2000, 2000],
  );
  assert.equal(gone, 1);
  client.stop();
});

test("a dropped connection reconnects and commands work again", async () => {
  const clock = makeClock();
  const children: FakeChild[] = [];
  let disconnects = 0;
  let connects = 0;
  const client = startControlClient({
    events: events({
      onConnect: () => connects++,
      onDisconnect: () => disconnects++,
    }),
    findTarget: () => Promise.resolve(TARGET),
    spawnChild: () => {
      const child = new FakeChild();
      children.push(child);
      return child;
    },
    timers: clock.timers,
    now: clock.now,
  });
  await flush();
  children[0]!.emit("%begin 1 1 1\n%end 1 1 1\n");
  await flush();
  children[0]!.exit();
  await flush();
  assert.equal(disconnects, 1);
  // The ladder restarts from its first rung after a successful connect.
  await clock.advance(100);
  assert.equal(children.length, 2);
  children[1]!.emit("%begin 1 1 1\n%end 1 1 1\n");
  await flush();
  assert.equal(connects, 2);
  const reply = client.command("list-clients");
  children[1]!.emit("%begin 2 2 1\nback\n%end 2 2 1\n");
  assert.equal(await reply, "back");
  client.stop();
});

test("a reply that never arrives times out and replaces the client", async () => {
  let disconnects = 0;
  const { clock, client } = await connected({
    onDisconnect: () => disconnects++,
  });
  const wedged = assert.rejects(client.command("list-panes"), /timed out/);
  await clock.advance(10_000);
  await wedged;
  assert.equal(disconnects, 1);
  client.stop();
});

// ----- the snapshot over the control socket ------------------------------

// Field order mirrors PANE_FORMAT (no session_attached: it derives from
// clients) and CLIENT_FORMAT (control_mode last) in src/data.ts.
function paneRow(
  session: string,
  paneId: string,
  over: Partial<Record<"rail" | "tty", string>> = {},
): string {
  return [
    "P",
    session,
    "@1",
    "1",
    "editor",
    "1",
    "2",
    "200",
    paneId,
    "0",
    over.tty ?? "/dev/ttys001",
    "34",
    "40",
    over.rail ?? "",
    "0",
    "0",
  ].join("\x1f");
}

function clientRow(
  session: string,
  over: Partial<
    Record<"termname" | "activity" | "flags" | "control", string>
  > = {},
): string {
  return [
    "C",
    session,
    "0",
    "root",
    over.termname ?? "xterm-ghostty",
    over.activity ?? "100",
    over.flags ?? "focused",
    over.control ?? "0",
  ].join("\x1f");
}

test("collectSnapshot through a runner sends both listings and filters control clients", async () => {
  const sent: string[] = [];
  const runner = (commandLine: string): Promise<string> => {
    sent.push(commandLine);
    if (commandLine.startsWith("list-panes")) {
      return Promise.resolve(
        [paneRow("main", "%1"), paneRow("other", "%2")].join("\n"),
      );
    }
    return Promise.resolve(
      [
        clientRow("main", { activity: "100" }),
        // The daemon's own control client: newer activity, no terminal.
        clientRow("other", { termname: "", activity: "999", control: "1" }),
      ].join("\n"),
    );
  };
  const { panes, clientFacts } = await collectSnapshot(runner);

  assert.equal(sent.length, 2);
  assert.match(sent[0]!, /^list-panes -a -F '/);
  assert.match(sent[1]!, /^list-clients -F '/);
  assert.match(sent[1]!, /client_control_mode/);

  // Attachment comes from REAL client rows, not #{session_attached}: the
  // control client's session does not count as attached.
  assert.equal(panes.length, 2);
  assert.equal(panes[0]!.sessionAttached, true);
  assert.equal(panes[1]!.sessionAttached, false);
  // Nor does it count as a client anywhere else.
  assert.equal(clientFacts.clientCount, 1);
  assert.equal(clientFacts.latestClientActivityTs, 100);
  assert.equal(clientFacts.latestClientIsKitty, true);
  assert.deepEqual([...clientFacts.attachedSessions], ["main"]);
  assert.deepEqual([...clientFacts.focusedSessions], ["main"]);
});

test("collectSnapshot facts match today's semantics for real clients", async () => {
  const runner = (commandLine: string): Promise<string> =>
    Promise.resolve(
      commandLine.startsWith("list-panes")
        ? paneRow("main", "%1", { rail: "1" })
        : [
            clientRow("main", {
              termname: "screen-256color",
              flags: "attached",
            }),
            clientRow("main", { activity: "200" }),
          ].join("\n"),
    );
  const { panes, clientFacts } = await collectSnapshot(runner);
  assert.equal(panes[0]!.isRail, true);
  assert.equal(clientFacts.clientCount, 2);
  assert.ok(clientFacts.nonKittySessions.has("main"));
  assert.equal(clientFacts.latestClientActivityTs, 200);
});
