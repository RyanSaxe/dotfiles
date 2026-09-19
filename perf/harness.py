#!/usr/bin/env -S uv run -q --script
# /// script
# requires-python = ">=3.12"
# ///
"""Synthetic-load performance harness for the navigation stack (PLAN.md §2).

Everything runs against a throwaway tmux server on an isolated socket with
a scratch HOME/XDG tree wired like the live one (symlinks into this repo);
PATH shims (perf/shims) stand in for workmux, vault, and the mascot
extractor. The live tmux server, the live rail daemon, and the real
~/.local/state are never touched — TMUX_TMPDIR fences every tmux path, and
the emitted report carries a per-run isolation section as proof.

Modes: `metrics` (latency matrix, p50/p95 over N runs), `assert` (the
pane-history behavior scenarios — the parity gate for the Phase 1 hook
rewrite, which must pass on today's code first), `all` (both).
"""

from __future__ import annotations

import argparse
import fcntl
import io
import math
import os
import pty
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHIMS = REPO / "perf" / "shims"
RESULTS = REPO / "perf" / "results"
GOTO_PANE = ".config/tmux/scripts/goto-pane.sh"
# The production M-l path: goto-pane's back mode.
GO_BACK_ARGS = (".config/tmux/scripts/goto-pane.sh", "back")

# Plain-text strings that only the named tab's body renders; capture-pane
# polling keys repaint detection on them.
REVIEWS_MARKER = "Review clear"
TASKS_MARKER = "fixture"

# Everything the daemon and the jump scripts wait on is asynchronous;
# generous ceilings keep a loaded run honest instead of flaky.
POLL_S = 0.01
SETTLE_TIMEOUT_S = float(os.environ.get("PERF_SETTLE_S", "10"))
BOOT_TIMEOUT_S = 30.0


class HarnessError(Exception):
    """A setup step or assertion the run cannot continue past."""


@dataclass
class Config:
    sessions: int
    windows: int
    agents: int
    busy: int
    runs: int
    churn_secs: float
    label: str
    mode: str
    scratch: Path | None
    keep: bool


@dataclass
class Metric:
    name: str
    samples_ms: list[float] = field(default_factory=list)
    note: str = ""
    censored: int = 0  # samples that hit the wait ceiling (lower bounds)


@dataclass
class ScenarioResult:
    name: str
    passed: bool
    detail: str


def env_int(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)))


def parse_args(argv: list[str]) -> Config:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode", nargs="?", default="all", choices=("metrics", "assert", "all")
    )
    parser.add_argument(
        "-n", "--sessions", type=int, default=env_int("PERF_SESSIONS", 8)
    )
    parser.add_argument("-m", "--windows", type=int, default=env_int("PERF_WINDOWS", 5))
    parser.add_argument("-k", "--agents", type=int, default=env_int("PERF_AGENTS", 12))
    parser.add_argument("-p", "--busy", type=int, default=env_int("PERF_BUSY", 8))
    parser.add_argument("-r", "--runs", type=int, default=env_int("PERF_RUNS", 20))
    parser.add_argument(
        "--churn",
        type=float,
        default=float(os.environ.get("PERF_CHURN_SECS", "1")),
        help="heartbeat churn interval in seconds; 0 disables",
    )
    parser.add_argument("--label", default=os.environ.get("PERF_LABEL", ""))
    parser.add_argument("--scratch", type=Path, default=None)
    parser.add_argument(
        "--keep", action="store_true", help="keep the scratch tree after the run"
    )
    parser.add_argument(
        "--profile",
        choices=("light",),
        default=None,
        help="light: N=2 M=2 K=2 P=0 runs=5",
    )
    args = parser.parse_args(argv)
    if args.profile == "light":
        args.sessions, args.windows, args.agents, args.busy = 2, 2, 2, 0
        args.runs = min(args.runs, 5)
    if args.sessions < 2 or args.windows < 2:
        parser.error("needs at least 2 sessions and 2 windows")
    label = args.label or (args.profile or "default")
    return Config(
        args.sessions,
        args.windows,
        args.agents,
        args.busy,
        args.runs,
        args.churn,
        label,
        args.mode,
        args.scratch,
        args.keep,
    )


def percentile(samples: list[float], q: float) -> float:
    ordered = sorted(samples)
    index = max(0, math.ceil(q * len(ordered)) - 1)
    return ordered[index]


class Harness:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        real_tmux = shutil.which("tmux")
        if real_tmux is None:
            raise HarnessError("tmux not on PATH")
        self.real_tmux = real_tmux
        self.sock = f"perf-{os.getpid()}"
        owns = cfg.scratch is None
        self.scratch = (
            cfg.scratch or Path(tempfile.mkdtemp(prefix="rail-perf."))
        ).resolve()
        self.owns_scratch = owns
        self.home = self.scratch / "home"
        self.state = self.home / ".local/state"
        self.rail_state = self.state / "dotfiles/rail"
        self.generated = self.state / "dotfiles/generated"
        self.agents_dir = self.state / "workmux/agents"
        self.counts = self.scratch / "counts"
        self.fixture_repo = self.scratch / "fixture-repo"
        # Unix socket paths cap near 104 bytes on macOS; fall back to the
        # system temp dir when the scratch path would overflow it.
        tmux_dir = self.scratch / "tmux"
        if len(str(tmux_dir)) > 60:
            tmux_dir = Path(tempfile.mkdtemp(prefix="rail-perf-sock."))
        self.tmux_tmpdir = tmux_dir
        self.base_env = self._make_env()
        self.tool_env = dict(self.base_env)
        self.procs: list[subprocess.Popen[bytes]] = []
        self.attach_proc: subprocess.Popen[bytes] | None = None
        self.attach_master: int | None = None
        self.metrics: list[Metric] = []
        self.scenarios: list[ScenarioResult] = []
        self.isolation: list[str] = []
        self.real_state_before: dict[str, float] = {}
        self.live_sessions_before: list[str] = []

    def _make_env(self) -> dict[str, str]:
        env = dict(os.environ)
        for key in (
            "TMUX",
            "TMUX_PANE",
            "TMUX_POPUP",
            "XDG_STATE_HOME",
            "XDG_CACHE_HOME",
            "XDG_CONFIG_HOME",
            "VIRTUAL_ENV",
            "STARSHIP_CONFIG",
            "ZDOTDIR",
        ):
            env.pop(key, None)
        env.update(
            {
                "HOME": str(self.home),
                "XDG_STATE_HOME": str(self.state),
                "XDG_CACHE_HOME": str(self.home / ".cache"),
                "TMPDIR": str(self.scratch / "tmp"),
                "TMUX_TMPDIR": str(self.tmux_tmpdir),
                "PATH": f"{SHIMS}:{os.environ['PATH']}",
                "PERF_TMUX_SOCK": self.sock,
                "PERF_REAL_TMUX": self.real_tmux,
                "PERF_COUNT_DIR": str(self.counts),
            }
        )
        return env

    # ----- plumbing ------------------------------------------------------

    def tmux(self, *args: str, check: bool = True) -> str:
        result = subprocess.run(
            [self.real_tmux, "-L", self.sock, *args],
            env=self.base_env,
            capture_output=True,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise HarnessError(f"tmux {' '.join(args)} failed: {result.stderr.strip()}")
        return result.stdout.rstrip("\n")

    def tool(
        self, *argv: str, cwd: Path | None = None, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            list(argv),
            env=self.tool_env,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            raise HarnessError(
                f"{argv[0]} failed ({result.returncode}): {result.stderr.strip()[:500]}"
            )
        return result

    def wait_for(
        self, what: str, pred: Callable[[], bool], timeout: float = SETTLE_TIMEOUT_S
    ) -> float:
        start = time.monotonic()
        while True:
            if pred():
                return (time.monotonic() - start) * 1000
            if time.monotonic() - start > timeout:
                raise HarnessError(f"timed out waiting for {what}")
            time.sleep(POLL_S)

    def wait_or_censor(
        self,
        metric: Metric,
        what: str,
        pred: Callable[[], bool],
        start: float,
        timeout: float = SETTLE_TIMEOUT_S,
    ) -> bool:
        """Metric-loop wait: a timeout is DATA under load, not a fatal error.

        Records the elapsed ceiling as a censored sample and counts it in
        the metric's note; behavior scenarios keep hard wait_for failures.
        """
        try:
            self.wait_for(what, pred, timeout)
            return True
        except HarnessError:
            metric.samples_ms.append((time.monotonic() - start) * 1000)
            metric.censored += 1
            return False

    def option(self, name: str) -> str:
        return self.tmux("show-options", "-gqv", name)

    def active_pane(self) -> tuple[str, str]:
        out = self.tmux("display-message", "-p", "#{session_name}\t#{pane_id}")
        session, _, pane = out.partition("\t")
        return session, pane

    def window_content_pane(self, target: str) -> str:
        rows = self.tmux(
            "list-panes",
            "-t",
            target,
            "-F",
            "#{pane_id}\t#{pane_active}\t#{?#{@rail},1,0}",
        )
        fallback = ""
        for row in rows.splitlines():
            pane, active, rail = row.split("\t")
            if rail == "1":
                continue
            if active == "1":
                return pane
            fallback = fallback or pane
        if not fallback:
            raise HarnessError(f"no content pane in {target}")
        return fallback

    def session_active_content_pane(self, session: str) -> str:
        window = self.tmux("display-message", "-p", "-t", session, "#{window_id}")
        return self.window_content_pane(window)

    def rail_pane(self, target: str) -> str:
        rows = self.tmux(
            "list-panes", "-t", target, "-F", "#{pane_id}\t#{?#{@rail},1,0}"
        )
        for row in rows.splitlines():
            pane, rail = row.split("\t")
            if rail == "1":
                return pane
        raise HarnessError(f"no rail pane in {target}")

    def count_lines(self, name: str) -> int:
        path = self.counts / f"{name}.count"
        try:
            return len(path.read_text().splitlines())
        except OSError:
            return 0

    def bat_cache_stamp(self) -> float:
        cache = self.home / ".cache/bat"
        newest = 0.0
        if cache.is_dir():
            for entry in cache.rglob("*"):
                newest = max(newest, entry.stat().st_mtime)
        return newest

    # ----- setup ---------------------------------------------------------

    def build_scratch(self) -> None:
        for path in (
            self.home / ".local/bin",
            self.home / ".config",
            self.home / ".local/share",
            self.rail_state,
            self.agents_dir,
            self.counts,
            self.scratch / "tmp",
            self.tmux_tmpdir,
            self.home / ".cache",
        ):
            path.mkdir(parents=True, exist_ok=True)
        links = {
            self.home / ".zshenv": REPO / "zsh/zshenv",
            self.home / ".zshrc": REPO / "zsh/zshrc",
            self.home / ".config/zsh": REPO / "zsh",
            self.home / ".config/tmux": REPO / "tmux",
            self.home / ".config/theme": REPO / "theme",
            self.home / ".local/bin/rail": REPO / "tuis/rail/bin/rail",
            self.home / ".local/bin/theme": REPO / "theme/bin/theme",
            # The daemon resolves the extractor by ABSOLUTE homedir path,
            # so the scratch home must point it at the shim.
            self.home / ".local/bin/mascot-accents": SHIMS / "mascot-accents",
        }
        for link, target in links.items():
            if not link.exists():
                link.symlink_to(target)
        # Plugins are COPIED, not linked: fast-theme writes into the plugin
        # tree on every interactive start, and those writes must land in
        # scratch, never in the live plugin checkout.
        real_plugins = Path.home() / ".local/share/zsh/plugins"
        scratch_plugins = self.home / ".local/share/zsh/plugins"
        if real_plugins.is_dir() and not scratch_plugins.exists():
            shutil.copytree(real_plugins, scratch_plugins)
        # Project -> mascot mapping for the flip metric; every real session
        # falls through to the tracked default identity.
        (self.state / "dotfiles").mkdir(parents=True, exist_ok=True)
        (self.state / "dotfiles/mascot.conf").write_text(
            "perf-alpha=perf:alpha\nperf-beta=perf:beta\n"
        )
        self._build_fixture_repo()

    def _build_fixture_repo(self) -> None:
        repo = self.fixture_repo
        repo.mkdir(parents=True, exist_ok=True)
        (repo / "package.json").write_text(
            '{\n  "name": "perf-fixture",\n  "version": "1.2.3"\n}\n'
        )
        (repo / "file.txt").write_text("fixture\n")
        git = [
            "git",
            "-C",
            str(repo),
            "-c",
            "user.email=perf@example.com",
            "-c",
            "user.name=perf",
        ]
        self.tool(*git[:3], "init", "-q")
        self.tool(*git, "add", ".")
        self.tool(*git, "commit", "-qm", "fixture")

    def theme_apply(self) -> None:
        self.tool(str(self.home / ".local/bin/theme"), "apply")
        if not (self.generated / "tuis-colors.json").is_file():
            raise HarnessError("theme apply produced no tuis-colors.json")

    def start_server(self) -> None:
        conf = str(REPO / "tmux/tmux.conf")
        size = ["-x", "220", "-y", "60"]
        self.tmux("-f", conf, "new-session", "-d", "-s", "perf-s0", *size, "/bin/sh")
        for index in range(1, self.cfg.sessions):
            self.tmux("new-session", "-d", "-s", f"perf-s{index}", *size, "/bin/sh")
        for index in range(self.cfg.sessions):
            for _ in range(self.cfg.windows - 1):
                self.tmux("new-window", "-d", "-t", f"perf-s{index}", "/bin/sh")
        socket_path = self.tmux("display-message", "-p", "#{socket_path}")
        self.tool_env["TMUX"] = f"{socket_path},0,0"
        self.tool_env["STARSHIP_CONFIG"] = str(self.generated / "starship.toml")

    def write_agent_fixtures(self) -> None:
        rows = self.tmux(
            "list-panes", "-a", "-F", "#{session_name}\t#{window_name}\t#{pane_id}"
        )
        candidates = [
            row.split("\t")
            for row in rows.splitlines()
            if not row.startswith("perf-s0\t")
        ]
        if not candidates:
            raise HarnessError("no panes outside perf-s0 for agents")
        now = int(time.time())
        for index in range(self.cfg.agents):
            session, window, pane = candidates[index % len(candidates)]
            (self.agents_dir / f"agent-{index}.json").write_text(
                "{"
                f'"session": "{session}", "window_name": "{window}", '
                f'"pane_id": "{pane}", "agent_kind": "claude", '
                f'"status": "working", "status_ts": {now - 3600 - index}, '
                f'"title": "perf agent {index}", "elapsed_secs": 900, '
                f'"updated_ts": {now}, "heartbeat_ts": {now}, '
                f'"worktree": "/perf/wt-{index}", '
                f'"branch": "perf-{index}", '
                f'"pane_key": {{"pane_id": "{pane}"}}'
                "}\n"
            )

    def write_hints_fixture(self) -> None:
        # A deterministic seed so `rail element` works even before the
        # daemon's first hints write; the daemon then overwrites it with
        # equivalent rows and the per-run resolver re-reads the file.
        agents = sorted(self.agents_dir.glob("agent-*.json"))
        lines = []
        for index, path in enumerate(agents[:9]):
            text = path.read_text()
            session = text.split('"session": "')[1].split('"')[0]
            pane = text.split('"pane_id": "')[1].split('"')[0]
            lines.append(f"perf-s0\t{index + 1}\t{session}\t{pane}")
        (self.rail_state / "hints.tsv").write_text("\n".join(lines) + "\n")

    def start_daemon(self) -> None:
        (self.rail_state / "enabled").touch()
        # NOT self.tool(): `rail ensure-daemon` backgrounds the daemon
        # through `npm exec`, whose bash layer keeps our stdout inherited
        # (only the final node redirects to the log). A capture pipe there
        # never sees EOF while the daemon lives, so capture_output would
        # block forever. Detach with DEVNULL stdio — production relies on
        # tmux run-shell not holding a pipe the same way.
        subprocess.run(
            [str(self.home / ".local/bin/rail"), "ensure-daemon"],
            env=self.tool_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        pid_file = self.rail_state / "daemon.pid"
        self.wait_for("daemon pidfile", pid_file.is_file, BOOT_TIMEOUT_S)
        want_rails = self.cfg.sessions * self.cfg.windows

        def rails_up() -> bool:
            out = self.tmux("list-panes", "-a", "-F", "#{?#{@rail},1,0}", check=False)
            return out.count("1") >= want_rails

        self.wait_for("rail panes", rails_up, BOOT_TIMEOUT_S)

    def attach_client(self) -> None:
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 60, 220, 0, 0))
        env = dict(self.base_env)
        env["TERM"] = "xterm-256color"
        self.attach_proc = subprocess.Popen(
            [self.real_tmux, "-L", self.sock, "attach-session", "-t", "perf-s0"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=env,
            start_new_session=True,
        )
        os.close(slave)
        self.attach_master = master

        def drain() -> None:
            while True:
                try:
                    if not os.read(master, 65536):
                        return
                except OSError:
                    return

        threading.Thread(target=drain, daemon=True).start()
        self.wait_for(
            "attached client",
            lambda: self.tmux("list-clients", "-F", "x", check=False) != "",
        )

    def start_load(self) -> None:
        if self.cfg.churn_secs > 0:
            self.procs.append(
                subprocess.Popen(
                    [str(SHIMS / "workmux"), "churn", str(self.cfg.churn_secs)],
                    env=self.tool_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            )
        # Duty-cycled busy loops: enough to pressure the scheduler and the
        # process table without pegging every core of the host.
        loop = (
            'while :; do i=0; while [ "$i" -lt 5000 ]; '
            "do i=$((i+1)); done; sleep 0.02; done"
        )
        for _ in range(self.cfg.busy):
            self.procs.append(
                subprocess.Popen(
                    ["/bin/sh", "-c", loop],
                    env=self.base_env,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            )

    def warmup_jump(self) -> None:
        # The first cross-session jump triggers the one-time default-mascot
        # render in the background; do it before anything is timed and let
        # the cascade drain.
        origin = self.window_content_pane("perf-s0:1")
        target = self.window_content_pane("perf-s1:1")
        self.goto(target)
        self.goto(origin)
        time.sleep(3)

    def run_script(self, *argv: str, target: str | None = None) -> None:
        # A pane's shell invokes these scripts (via the M-l/jump bindings'
        # run-shell) with $TMUX_PANE set to that pane, and goto-pane's
        # origin capture — `display-message -p` with no -t — reads it.
        # Drive them the same way: a subprocess with TMUX_PANE pinned to
        # the origin pane. Without it, an external display-message falls
        # back to the most-recent SESSION, which selfHeal keeps bumping on
        # other sessions — the wrong origin under load.
        pane = target or self.active_pane()[1]
        env = dict(self.tool_env, TMUX_PANE=pane)
        result = subprocess.run(
            list(argv), env=env, capture_output=True, text=True, check=False
        )
        if result.returncode != 0:
            raise HarnessError(
                f"{argv[0]} failed ({result.returncode}): {result.stderr.strip()[:300]}"
            )

    def goto(self, pane: str, quiet: str = "quiet") -> None:
        script = str(self.home / GOTO_PANE)
        session = self.tmux("display-message", "-p", "-t", pane, "#{session_name}")
        # Positioning: the origin does not matter (quiet, no history write
        # when it would move), but pin TMUX_PANE anyway for consistency.
        self.run_script(script, session, pane, pane, quiet, target=pane)
        self.wait_for(f"client on {pane}", lambda: self.active_pane()[1] == pane)

    # ----- metrics -------------------------------------------------------

    def metric_window_select(self) -> None:
        cmd = Metric("window-select cmd")
        drain = Metric("window-select drain", note="until @TMUX_CURR_PANE converges")
        self.tmux("select-window", "-t", "perf-s0:1")
        time.sleep(0.3)
        for run in range(self.cfg.runs):
            target = f"perf-s0:{2 if run % 2 == 0 else 1}"
            expected = self.window_content_pane(target)
            start = time.monotonic()
            self.tmux("select-window", "-t", target)
            cmd.samples_ms.append((time.monotonic() - start) * 1000)
            if self.wait_or_censor(
                drain,
                "history convergence",
                lambda want=expected: self.option("@TMUX_CURR_PANE") == want,
                start,
            ):
                drain.samples_ms.append((time.monotonic() - start) * 1000)
        self.metrics += [cmd, drain]

    def metric_go_back(self) -> None:
        metric = Metric("alt+L end-to-end", note="landing asserted")
        script = str(self.home / GO_BACK_ARGS[0])
        origin = self.window_content_pane("perf-s0:1")
        away = self.window_content_pane("perf-s1:1")
        self.goto(origin)
        self.goto(away)  # seeds PREV=origin
        misses: list[str] = []
        for _ in range(self.cfg.runs):
            # The jump's history write rides the hook queue; wait until
            # PREV points at the OTHER pane of the bounce pair before
            # trusting it as the expected landing.
            _, here = self.active_pane()
            seed_start = time.monotonic()
            if not self.wait_or_censor(
                metric,
                "history write",
                lambda pane=here: self.option("@TMUX_PREV_PANE") not in ("", pane),
                seed_start,
            ):
                misses.append(
                    f"seed: PREV={self.option('@TMUX_PREV_PANE')!r} here={here}"
                )
                self.goto(origin)
                self.goto(away)
                continue
            expected = self.option("@TMUX_PREV_PANE")
            start = time.monotonic()
            self.run_script(script, "back")
            if not self.wait_or_censor(
                metric,
                "go-back landing",
                lambda want=expected: self.active_pane()[1] == want,
                start,
            ):
                misses.append(
                    f"land: want={expected} got={self.active_pane()[1]} "
                    f"PREV={self.option('@TMUX_PREV_PANE')!r} "
                    f"CURR={self.option('@TMUX_CURR_PANE')!r}"
                )
                self.goto(origin)
                self.goto(away)
                continue
            metric.samples_ms.append((time.monotonic() - start) * 1000)
        if misses:
            metric.note += f" [{len(misses)} timeouts: {'; '.join(misses[:3])}]"
        self.metrics.append(metric)

    def _popup_shell_once(self) -> float:
        master, slave = pty.openpty()
        env = dict(self.tool_env)
        env["TMUX_POPUP"] = "1"
        env["TERM"] = "xterm-256color"
        start = time.monotonic()
        proc = subprocess.Popen(
            ["zsh", "-ic", "exit"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            env=env,
            cwd=self.home,
            start_new_session=True,
        )
        os.close(slave)
        while True:
            try:
                if not os.read(master, 65536):
                    break
            except OSError:
                break
        proc.wait()
        elapsed = (time.monotonic() - start) * 1000
        os.close(master)
        return elapsed

    def metric_popup_shell(self) -> None:
        warm = Metric("popup shell start (warm)")
        cold = Metric("popup shell start (cold)", note="zcompdump removed")
        self._popup_shell_once()  # prime the dump once
        for _ in range(self.cfg.runs):
            warm.samples_ms.append(self._popup_shell_once())
        for _ in range(self.cfg.runs):
            for dump in self.home.glob(".zcompdump*"):
                dump.unlink()
            cold.samples_ms.append(self._popup_shell_once())
        self.metrics += [warm, cold]

    def resolve_hint(self, digit: str) -> str:
        for line in (self.rail_state / "hints.tsv").read_text().splitlines():
            fields = line.split("\t")
            if len(fields) == 4 and fields[0] == "perf-s0" and fields[1] == digit:
                return fields[3]
        raise HarnessError(f"no perf-s0 hint for digit {digit}")

    def metric_element_jump(self) -> None:
        metric = Metric("element jump", note="rail element 1, landing asserted")
        rail = str(self.home / ".local/bin/rail")
        origin = self.window_content_pane("perf-s0:1")
        self.goto(origin)
        for _ in range(self.cfg.runs):
            expected = self.resolve_hint("1")
            start = time.monotonic()
            self.tool(rail, "element", "1")
            if self.wait_or_censor(
                metric,
                "element landing",
                lambda want=expected: self.active_pane()[1] == want,
                start,
                timeout=max(15.0, SETTLE_TIMEOUT_S),
            ):
                metric.samples_ms.append((time.monotonic() - start) * 1000)
            self.goto(origin)
        self.metrics.append(metric)

    def _tab_repaint_once(self, metric: Metric, tab: str, marker: str) -> None:
        rail = self.rail_pane("perf-s0:1")
        start = time.monotonic()
        (self.rail_state / "tab").write_text(f"{tab}\n")
        if self.wait_or_censor(
            metric,
            f"{tab} repaint",
            lambda: marker in self.tmux("capture-pane", "-p", "-t", rail, check=False),
            start,
        ):
            metric.samples_ms.append((time.monotonic() - start) * 1000)

    def metric_tab_repaint(self) -> None:
        reviews = Metric("tab write -> repaint (reviews)")
        tasks = Metric("tab write -> repaint (tasks)")
        self.tmux("select-window", "-t", "perf-s0:1")
        for _ in range(self.cfg.runs):
            self._tab_repaint_once(tasks, "tasks", TASKS_MARKER)
            self._tab_repaint_once(reviews, "reviews", REVIEWS_MARKER)
        (self.rail_state / "tab").write_text("agents\n")
        self.metrics += [tasks, reviews]

    def metric_prompt_collector(self) -> None:
        metric = Metric(
            "prompt collector", note="dash prompt-segments.sh in fixture repo"
        )
        script = str(REPO / "zsh/prompt-segments.sh")
        self.tool("dash", script, cwd=self.fixture_repo)  # warm caches
        for _ in range(self.cfg.runs):
            start = time.monotonic()
            self.tool("dash", script, cwd=self.fixture_repo)
            metric.samples_ms.append((time.monotonic() - start) * 1000)
        self.metrics.append(metric)

    def metric_theme_sync(self) -> None:
        theme = str(self.home / ".local/bin/theme")
        noop = Metric("mascot sync (noop)", note="same mascot, early exit")
        flip = Metric("mascot sync (flip)")
        self.tool(theme, "mascot", "sync", "perf-alpha")
        for _ in range(self.cfg.runs):
            start = time.monotonic()
            self.tool(theme, "mascot", "sync", "perf-alpha")
            noop.samples_ms.append((time.monotonic() - start) * 1000)
        extractor_calls = 0
        bat_rebuilds = 0
        for run in range(self.cfg.runs):
            project = "perf-beta" if run % 2 == 0 else "perf-alpha"
            before_calls = self.count_lines("mascot-accents")
            before_bat = self.bat_cache_stamp()
            start = time.monotonic()
            self.tool(theme, "mascot", "sync", project)
            flip.samples_ms.append((time.monotonic() - start) * 1000)
            extractor_calls += self.count_lines("mascot-accents") - before_calls
            if self.bat_cache_stamp() > before_bat:
                bat_rebuilds += 1
        flip.note = (
            f"{extractor_calls} extractor calls, "
            f"{bat_rebuilds} bat rebuilds over {self.cfg.runs} "
            "flips"
        )
        self.metrics += [noop, flip]
        # Leave the default mascot active so later jumps early-exit.
        self.tool(theme, "mascot", "sync", "perf-unmapped")
        time.sleep(2)

    def run_metrics(self) -> None:
        self.metric_window_select()
        self.metric_go_back()
        self.metric_element_jump()
        self.metric_tab_repaint()
        self.metric_popup_shell()
        self.metric_prompt_collector()
        self.metric_theme_sync()

    # ----- behavior scenarios -------------------------------------------

    def check(self, name: str, passed: bool, detail: str) -> None:
        self.scenarios.append(ScenarioResult(name, passed, detail))
        print(
            f"{'PASS' if passed else 'FAIL'} {name}" + ("" if passed else f": {detail}")
        )

    def settle_history(self) -> tuple[str, str]:
        stable_since = time.monotonic()
        last = ("", "")
        deadline = time.monotonic() + SETTLE_TIMEOUT_S
        while time.monotonic() < deadline:
            now = (self.option("@TMUX_CURR_PANE"), self.option("@TMUX_PREV_PANE"))
            if now != last:
                last = now
                stable_since = time.monotonic()
            elif time.monotonic() - stable_since > 0.6:
                return now
            time.sleep(0.05)
        return last

    def scenario_dedupe(self) -> None:
        window = "perf-s0:1"
        self.tmux("select-window", "-t", window)
        pane_a = self.window_content_pane(window)
        pane_b = self.tmux(
            "split-window", "-t", window, "-P", "-F", "#{pane_id}", "/bin/sh"
        )
        self.settle_history()
        for target in (pane_a, pane_b, pane_a, pane_a):
            self.tmux("select-pane", "-t", target)
            time.sleep(0.15)
        curr, prev = self.settle_history()
        self.check(
            "A->B->A dedupe",
            curr == pane_a and prev == pane_b,
            f"CURR={curr} PREV={prev}, want CURR={pane_a} PREV={pane_b}",
        )
        self.tmux("kill-pane", "-t", pane_b)
        time.sleep(0.3)

    def scenario_cross_session(self) -> tuple[str, str]:
        seat = self.window_content_pane("perf-s0:1")
        self.goto(seat)
        self.settle_history()
        # The origin is wherever the client actually sits now — read it,
        # never assume it. The jump must record exactly this pane as PREV.
        origin_session, origin = self.active_pane()
        # A clean single-hop cross-session jump: target the other
        # session's ACTIVE window, so switch-client lands directly on the
        # target with no intervening select-window. (A jump to a
        # non-active window of that session adds an intermediate focus
        # event; the native pane-history hooks and goto-pane's HIST_LOCK
        # keep that from corrupting the pair. This scenario asserts the
        # round-trip semantic directly.)
        target = self.session_active_content_pane("perf-s1")
        self.run_script(
            str(self.home / GOTO_PANE), "perf-s1", target, target, target=origin
        )
        self.wait_for("jump landing", lambda: self.active_pane()[1] == target)
        curr, prev = self.settle_history()
        session = self.active_pane()[0]
        self.check(
            "cross-session jump",
            origin_session == "perf-s0"
            and session == "perf-s1"
            and curr == target
            and prev == origin,
            f"origin={origin_session}/{origin} landed={session} "
            f"CURR={curr} PREV={prev}, want origin on perf-s0 and "
            f"perf-s1/{target}/{origin}",
        )
        return origin, target

    def scenario_go_back(self, origin: str, target: str) -> None:
        self.run_script(str(self.home / GO_BACK_ARGS[0]), GO_BACK_ARGS[1])
        self.wait_for("go-back landing", lambda: self.active_pane()[1] == origin)
        curr, prev = self.settle_history()
        self.check(
            "alt+L round-trip",
            curr == origin and prev == target,
            f"CURR={curr} PREV={prev}, want CURR={origin} PREV={target}",
        )

    def scenario_killed_prev(self) -> None:
        window = "perf-s0:1"
        self.tmux("select-window", "-t", window)
        pane_a = self.window_content_pane(window)
        self.goto(pane_a)
        temp = self.tmux(
            "split-window", "-t", window, "-P", "-F", "#{pane_id}", "/bin/sh"
        )
        # The split leaves temp active but unrecorded (after-split-window is
        # deliberately unset in tmux.conf). Re-seat on pane_a, then make two
        # real focus moves so temp lands in history as PREV.
        self.tmux("select-pane", "-t", pane_a)
        self.wait_for("CURR=pane_a", lambda: self.option("@TMUX_CURR_PANE") == pane_a)
        self.tmux("select-pane", "-t", temp)
        self.wait_for("CURR=temp", lambda: self.option("@TMUX_CURR_PANE") == temp)
        self.tmux("select-pane", "-t", pane_a)
        self.wait_for("PREV=temp", lambda: self.option("@TMUX_PREV_PANE") == temp)
        self.tmux("kill-pane", "-t", temp)
        time.sleep(0.3)
        self.run_script(str(self.home / GO_BACK_ARGS[0]), GO_BACK_ARGS[1])
        time.sleep(0.5)
        _, pane = self.active_pane()
        prev = self.option("@TMUX_PREV_PANE")
        self.check(
            "killed-prev clears",
            pane == pane_a and prev == "",
            f"pane={pane} PREV={prev!r}, want pane={pane_a} PREV=''",
        )

    def scenario_rail_excluded(self) -> None:
        window = "perf-s0:1"
        self.tmux("select-window", "-t", window)
        rail = self.rail_pane(window)
        self.tmux("select-pane", "-t", rail)
        time.sleep(0.5)
        curr, prev = self.settle_history()
        _, pane = self.active_pane()
        self.check(
            "rail never in history",
            rail not in (curr, prev, pane),
            f"rail={rail} CURR={curr} PREV={prev} active={pane}",
        )

    def scenario_spam(self) -> None:
        origin, target = (
            self.window_content_pane("perf-s0:1"),
            self.window_content_pane("perf-s1:1"),
        )
        self.goto(origin)
        self.goto(target)
        self.settle_history()
        script = str(self.home / GO_BACK_ARGS[0])
        _, seat = self.active_pane()
        # Ten concurrent go-backs, exactly how ten fast M-l presses would
        # land — each pinned via TMUX_PANE to the pane the presses fired
        # in, all racing the single server command queue.
        env = dict(self.tool_env, TMUX_PANE=seat)
        procs = [
            subprocess.Popen(
                [script, "back"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            for _ in range(10)
        ]
        for proc in procs:
            proc.wait(timeout=30)
        time.sleep(0.5)
        curr, prev = self.settle_history()
        _, pane = self.active_pane()
        lock = self.option("@TMUX_HIST_LOCK")
        pair_ok = {curr, prev} == {origin, target}
        self.check(
            "10x alt+L spam sane",
            pair_ok and curr == pane and lock in ("", "0"),
            f"CURR={curr} PREV={prev} active={pane} lock={lock!r}, "
            f"want pair {{{origin},{target}}} and CURR==active",
        )
        # And the history still works: one more go-back must land on PREV.
        expected = prev
        self.run_script(script, "back")
        landed = True
        try:
            self.wait_for(
                "post-spam go-back", lambda: self.active_pane()[1] == expected
            )
        except HarnessError:
            landed = False
        self.check(
            "post-spam go-back lands", landed, f"client did not reach {expected}"
        )

    def run_scenarios(self) -> None:
        self.scenario_dedupe()
        origin, target = self.scenario_cross_session()
        self.scenario_go_back(origin, target)
        self.scenario_killed_prev()
        self.scenario_rail_excluded()
        self.scenario_spam()

    # ----- isolation proof ----------------------------------------------

    def _real_state_snapshot(self) -> dict[str, float]:
        # workmux is included because the shimmed daemon's one bypass route
        # (a PATH leak reaching the real workmux) would land its writes there.
        snapshot: dict[str, float] = {}
        for root in (
            Path.home() / ".local/state/dotfiles",
            Path.home() / ".local/state/workmux",
        ):
            if root.is_dir():
                for entry in root.rglob("*"):
                    if entry.is_file():
                        snapshot[str(entry)] = entry.stat().st_mtime
        return snapshot

    def _live_sessions(self) -> list[str]:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F", "#{session_name}"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return ["<no live server>"]
        return sorted(result.stdout.split())

    def snapshot_before(self) -> None:
        self.real_state_before = self._real_state_snapshot()
        self.live_sessions_before = self._live_sessions()

    def verify_isolation(self) -> None:
        after = self._real_state_snapshot()
        changed = sorted(
            path
            for path, mtime in after.items()
            if self.real_state_before.get(path) != mtime
        )
        added = sorted(set(after) - set(self.real_state_before))
        if changed or added:
            self.isolation.append(
                "real ~/.local/state/{dotfiles,workmux} files with new mtimes "
                "(the LIVE rail daemon keeps writing its own state; "
                "nothing in the harness holds these paths): "
                + ", ".join(changed + added)
            )
        else:
            self.isolation.append(
                "real ~/.local/state/{dotfiles,workmux}: no file changed during the run"
            )
        live_after = self._live_sessions()
        if live_after == self.live_sessions_before:
            self.isolation.append(
                "live tmux server sessions unchanged: " + ", ".join(live_after)
            )
        else:
            self.isolation.append(
                f"live tmux sessions CHANGED: {self.live_sessions_before} "
                f"-> {live_after}"
            )
        pid = self._daemon_pid()
        if pid is not None:
            result = subprocess.run(
                ["ps", "-E", "-ww", "-o", "command=", "-p", str(pid)],
                capture_output=True,
                text=True,
                check=False,
            )
            scoped = f"HOME={self.home}" in result.stdout
            self.isolation.append(
                f"scratch daemon pid {pid} env HOME points at scratch: {scoped}"
            )

    # ----- reporting -----------------------------------------------------

    def write_results(self) -> Path:
        RESULTS.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        base = RESULTS / f"{stamp}-{self.cfg.label}"
        version = (
            self.tmux("display-message", "-p", "#{version}", check=False) or "unknown"
        )
        tsv_lines = ["metric\trun\tms"]
        for metric in self.metrics:
            for index, sample in enumerate(metric.samples_ms):
                tsv_lines.append(f"{metric.name}\t{index}\t{sample:.2f}")
        (base.with_suffix(".tsv")).write_text("\n".join(tsv_lines) + "\n")

        lines = [
            f"# rail perf harness — {self.cfg.label}",
            "",
            f"- when: {time.strftime('%Y-%m-%d %H:%M:%S %z')}",
            (
                f"- load: {self.cfg.sessions} sessions x {self.cfg.windows} "
                f"windows, {self.cfg.agents} agents, {self.cfg.busy} busy "
                f"procs, churn {self.cfg.churn_secs}s"
            ),
            f"- runs per metric: {self.cfg.runs}",
            f"- tmux: {version}",
            "",
        ]
        if self.metrics:
            lines += [
                "## Metrics",
                "",
                "| metric | runs | p50 ms | p95 ms | min | max | notes |",
                "| --- | --- | --- | --- | --- | --- | --- |",
            ]
            for metric in self.metrics:
                samples = metric.samples_ms
                if not samples:
                    lines.append(
                        f"| {metric.name} | 0 | - | - | - | - | {metric.note} |"
                    )
                    continue
                censor = (
                    f"{metric.censored} censored at ceiling; "
                    if metric.censored
                    else ""
                )
                lines.append(
                    f"| {metric.name} | {len(samples)} "
                    f"| {percentile(samples, 0.5):.1f} "
                    f"| {percentile(samples, 0.95):.1f} "
                    f"| {min(samples):.1f} | {max(samples):.1f} "
                    f"| {censor}{metric.note} |"
                )
            lines.append("")
        if self.scenarios:
            lines += ["## Behavior scenarios", ""]
            for scenario in self.scenarios:
                status = "PASS" if scenario.passed else "FAIL"
                detail = "" if scenario.passed else f" — {scenario.detail}"
                lines.append(f"- {status}: {scenario.name}{detail}")
            lines.append("")
        lines += ["## Isolation", ""]
        lines += [f"- {note}" for note in self.isolation]
        lines.append("")
        md = base.with_suffix(".md")
        md.write_text("\n".join(lines))
        return md

    # ----- lifecycle -----------------------------------------------------

    def _daemon_pid(self) -> int | None:
        try:
            pid = int((self.rail_state / "daemon.pid").read_text())
        except (OSError, ValueError):
            return None
        result = subprocess.run(
            ["ps", "-o", "command=", "-p", str(pid)],
            capture_output=True,
            text=True,
            check=False,
        )
        # Match both the tsx source form and the bundled dist form — the
        # same pattern bin/rail and the daemon use for liveness.
        alive = re.search(r"rail.*daemon\.(ts|mjs)", result.stdout) is not None
        return pid if alive else None

    def teardown(self) -> None:
        pid = self._daemon_pid()
        if pid is not None:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        for proc in self.procs:
            # Whole process group: the churn/busy loops keep `sleep`
            # children that a bare terminate would orphan for a beat.
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except OSError:
                proc.terminate()
        subprocess.run(
            [self.real_tmux, "-L", self.sock, "kill-server"],
            env=self.base_env,
            capture_output=True,
            check=False,
        )
        if self.attach_proc is not None:
            self.attach_proc.terminate()
            try:
                self.attach_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.attach_proc.kill()
        if self.attach_master is not None:
            try:
                os.close(self.attach_master)
            except OSError:
                pass
        for proc in self.procs:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        if pid is not None:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and self._daemon_pid() == pid:
                time.sleep(0.1)
            if self._daemon_pid() == pid:
                os.kill(pid, signal.SIGKILL)
        if self.tmux_tmpdir != self.scratch / "tmux":
            shutil.rmtree(self.tmux_tmpdir, ignore_errors=True)
        if self.owns_scratch and not self.cfg.keep:
            shutil.rmtree(self.scratch, ignore_errors=True)
        else:
            print(f"scratch kept at {self.scratch}")

    def run(self) -> int:
        print(f"scratch: {self.scratch}")
        print(f"socket:  {self.sock} (TMUX_TMPDIR={self.tmux_tmpdir})")
        self.snapshot_before()
        self.build_scratch()
        self.theme_apply()
        self.start_server()
        self.write_agent_fixtures()
        self.write_hints_fixture()
        self.start_daemon()
        self.attach_client()
        self.start_load()
        self.warmup_jump()
        if self.cfg.mode in ("metrics", "all"):
            self.run_metrics()
        if self.cfg.mode in ("assert", "all"):
            self.run_scenarios()
        self.verify_isolation()
        report = self.write_results()
        print(f"report:  {report}")
        for metric in self.metrics:
            print(
                f"{metric.name}: p50={percentile(metric.samples_ms, 0.5):.1f}ms "
                f"p95={percentile(metric.samples_ms, 0.95):.1f}ms "
                f"({len(metric.samples_ms)} runs)"
                + (f" [{metric.note}]" if metric.note else "")
            )
        for note in self.isolation:
            print(f"isolation: {note}")
        failed = [s for s in self.scenarios if not s.passed]
        return 1 if failed else 0


def main(argv: list[str]) -> int:
    # Line-buffer so a backgrounded run streams progress instead of
    # withholding it until exit (isinstance narrows for the type checker).
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(line_buffering=True)
    cfg = parse_args(argv)
    harness = Harness(cfg)
    try:
        return harness.run()
    finally:
        harness.teardown()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
