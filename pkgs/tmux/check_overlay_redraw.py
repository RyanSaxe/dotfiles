# /// script
# requires-python = ">=3.11"
# ///
"""Check that tmux delivers a popup's output written while a window redraw is
deferred, and leaves a popup that wrote nothing alone.

It attaches a client to a pty and fills that pty, so tmux can write the
client nothing more. It scrolls a pane under an open popup, which makes tmux
defer a window redraw, and then reads the pty. It does that twice:

1. The popup prints nothing meanwhile. tmux should redraw the window and
   not the popup, whose QUIET it has already sent.
2. The popup prints MARKER meanwhile. A tmux that then redraws the popup
   with the window sends MARKER, and one that leaves the popup out never
   does.

usage: check_overlay_redraw.py [TMUX_BINARY]   (exit 0 pass, 1 fail)
"""

import fcntl
import os
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

tmux = sys.argv[1] if len(sys.argv) > 1 else "tmux"
T = [tmux, "-L", f"overlay-check-{os.getpid()}", "-f", "/dev/null"]
# Without TMUX, so the check also runs from inside a tmux session.
env = {k: v for k, v in os.environ.items() if k not in ("TMUX", "TMUX_PANE")}
env["TERM"] = "xterm-256color"

subprocess.run(T + ["new-session", "-d", "-x", "100", "-y", "30", "sh"], check=True, env=env)
terminal, client_tty = os.openpty()
fcntl.ioctl(client_tty, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
client = subprocess.Popen(
    T + ["attach"], env=env, stdin=client_tty, stdout=client_tty, stderr=client_tty, start_new_session=True
)
out = bytearray()


def read_for(seconds, until=None):
    end = time.monotonic() + seconds
    while time.monotonic() < end and not (until and until in out):
        ready, _, _ = select.select([terminal], [], [], 0.02)
        if ready:
            out.extend(os.read(terminal, 65536))


def wait_until(happened, what):
    end = time.monotonic() + 30
    while not happened():
        if time.monotonic() > end:
            sys.exit(f"FAIL: timed out waiting for {what}")
        time.sleep(0.02)


def fill_pty():
    """Write to the client's pty until it holds no more.

    A pty holds 1 KB on macOS and 20 KB on Linux. tmux defers a redraw only
    while its output to the client is waiting, so a pty with room left would
    take that output and hide the bug.
    """
    tty = os.open(os.ttyname(client_tty), os.O_WRONLY | os.O_NONBLOCK | os.O_NOCTTY)
    try:
        while True:
            os.write(tty, b"\0" * 256)
    except BlockingIOError:
        pass
    finally:
        os.close(tty)


def tm(*args):
    return subprocess.run(T + list(args), check=True, env=env, capture_output=True, text=True).stdout


def scroll_behind_full_pty(last_line):
    """Fill the pty and scroll the pane under the popup.

    tmux marks the pane for a redraw, and defers that redraw while the pty
    is full.
    """
    fill_pty()
    tm("send-keys", "-t", "0", f"seq 1 {last_line}", "Enter")
    wait_until(lambda: f"\n{last_line}\n" in tm("capture-pane", "-p", "-t", "0"), "the pane to scroll")


failure = "the check did not finish"
socket = None
with tempfile.TemporaryDirectory() as signals:
    go, printed = os.path.join(signals, "go"), os.path.join(signals, "printed")
    try:
        # tmux asks a new client's terminal what it supports, and redraws
        # everything when no answer has come after five seconds. Nothing
        # answers here, so the check starts after that redraw.
        read_for(5.5)
        socket = tm("display-message", "-p", "#{socket_path}").strip()
        name = tm("list-clients", "-F", "#{client_name}").strip()
        # display-popup returns only when the popup closes, so it runs
        # alongside. The popup prints MARKER once `go` exists.
        subprocess.Popen(
            T
            + ["display-popup", "-c", name, "-w", "60", "-h", "10", "-E"]
            + [f"printf QUIET; until [ -e {go} ]; do sleep 0.05; done; printf MARKER; touch {printed}; sleep 30"],
            env=env,
        )
        read_for(5.0, until=b"QUIET")

        scroll_behind_full_pty(2000)
        time.sleep(0.5)
        mark = len(out)
        read_for(1.5)
        repainted = b"QUIET" in out[mark:]

        scroll_behind_full_pty(3000)
        open(go, "w").close()
        wait_until(lambda: os.path.exists(printed), "the popup to print")
        time.sleep(0.5)  # tmux reads the popup's output
        mark = len(out)
        read_for(3.0, until=b"MARKER")
        delivered = b"MARKER" in out[mark:]

        if not delivered:
            failure = "the popup's output never reached the terminal"
        elif repainted:
            failure = "tmux redrew a popup that had printed nothing"
        else:
            failure = None
    finally:
        subprocess.run(T + ["kill-server"], env=env, capture_output=True)
        os.close(client_tty)
        os.close(terminal)
        client.wait()
        # tmux leaves the socket of a server killed with a popup open.
        if socket and os.path.exists(socket):
            os.unlink(socket)
print(f"FAIL: {failure}" if failure else "pass: tmux redrew the popup only for the popup's own output")
sys.exit(1 if failure else 0)
