package main

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	"workspace/mux"
)

// Attention is what sketchybar's A, R and T letters show. The agent level
// comes from the agents' statuses, the review level from the inbox, and the
// task level from the vault. The files under ~/.local/state/ws are what
// --watch last published, for sketchybar and Reviews to read.

// agentBackend is the multiplexer whose agents count. Outside a terminal, as
// the --watch job runs, it follows ws focus: Rex when it's installed, and
// tmux otherwise.
func agentBackend(b mux.Backend) mux.Backend {
	if b.Inside() {
		return b
	}
	if _, err := exec.LookPath("rex"); err == nil {
		return mux.Rex{}
	}
	return b
}

// agentLevel is waiting when a program is blocked on you or failed, and none
// otherwise. A finished agent doesn't count: neither multiplexer tells ws when
// you've looked at one, so it would stay lit until the agent ran again.
func agentLevel(b mux.Backend) (string, error) {
	s, err := b.Snapshot()
	for _, p := range s.Agents() {
		if p.Status <= mux.Error {
			return "waiting", err
		}
	}
	return "none", err
}

// reviewLevel is ci when a red check on one of your pull requests needs
// you, review when anything else in the inbox does, and none otherwise.
func reviewLevel(in inbox, a acks) string {
	level := "none"
	for _, it := range in.Items {
		if a.standing(it) != needsYou {
			continue
		}
		if it.Reasons[0].Kind == failing {
			return "ci"
		}
		level = "review"
	}
	return level
}

// taskLevel is overdue when an open task is past its date, today when one is
// due today, tomorrow when one is due tomorrow, and none otherwise.
func taskLevel(ts []task, today time.Time) string {
	tomorrow := today.AddDate(0, 0, 1).Format(time.DateOnly)
	level := "none"
	for _, t := range ts {
		switch {
		case t.Done:
		case t.State == "overdue":
			return "overdue"
		case t.State == "today":
			level = "today"
		case t.Due == tomorrow && level == "none":
			level = "tomorrow"
		}
	}
	return level
}

// vaultTaskLevel is the taskLevel of the vault's tasks, and none on a
// computer without a vault, so its T letter stays off.
func vaultTaskLevel(now time.Time) (string, error) {
	vault := vaultDir()
	if vault == "" {
		return "none", nil
	}
	ts, err := vaultTasks(vault, now)
	return taskLevel(ts, now), err
}

func attention(b mux.Backend, watch bool) error {
	b = agentBackend(b)
	if watch {
		return watchAttention(b)
	}
	agents, err := agentLevel(b)
	if err != nil {
		return err
	}
	var in inbox
	var a acks
	readJSON("inbox.json", &in)
	readJSON("acknowledged.json", &a)
	tasks, err := vaultTaskLevel(time.Now())
	if err != nil {
		return err
	}
	fmt.Println(agents, reviewLevel(in, a), tasks)
	return nil
}

// publish writes level to the named file and tells sketchybar, but only when
// the file holds a different level.
func publish(name, level string) {
	if old, _ := os.ReadFile(filepath.Join(stateDir, name)); string(old) == level {
		return
	}
	if err := writeWhole(name, []byte(level)); err != nil {
		fmt.Fprintln(os.Stderr, "ws:", err)
		return
	}
	exec.Command("sketchybar", "--trigger", strings.TrimSuffix(name, "-attention")+"_attention_change").Run()
}

// watchAttention republishes the agent level whenever b reports a status
// change, fetches the inbox every 5 minutes and rereads the vault's tasks
// every minute, which also catches a new day. It is the only process that
// fetches the inbox. SIGUSR1 asks it to fetch now, as Ctrl-R in Reviews does,
// and SIGUSR2 to republish the review level, after an acknowledgement. It
// runs until it is killed.
func watchAttention(b mux.Backend) error {
	if err := writeWhole("attention.pid", []byte(strconv.Itoa(os.Getpid()))); err != nil {
		return err
	}
	// A signal already waiting covers any more, since one recount sees both.
	changed := make(chan struct{}, 1)
	go b.Follow(func() {
		select {
		case changed <- struct{}{}:
		default:
		}
	})
	asked := make(chan os.Signal, 1)
	signal.Notify(asked, syscall.SIGUSR1, syscall.SIGUSR2)
	var in inbox
	readJSON("inbox.json", &in)
	republish := func() {
		var a acks
		readJSON("acknowledged.json", &a)
		publish("review-attention", reviewLevel(in, a))
	}
	refresh := func() {
		next, err := fetchInbox(in, watchList(), ignoreList(), time.Now())
		if err != nil {
			fmt.Fprintln(os.Stderr, "ws: reviews:", err)
			return
		}
		if err := writeJSON("inbox.json", next); err != nil {
			fmt.Fprintln(os.Stderr, "ws: reviews:", err)
			return
		}
		in = next
		republish()
	}
	recount := func() {
		level, err := vaultTaskLevel(time.Now())
		if err != nil {
			fmt.Fprintln(os.Stderr, "ws: tasks:", err)
			return
		}
		publish("task-attention", level)
	}
	reviews := time.NewTicker(5 * time.Minute)
	tasks := time.NewTicker(time.Minute)
	refresh()
	recount()
	for {
		select {
		case <-tasks.C:
			recount()
		case <-changed:
			// A burst of reports, such as an agent finishing, settles first.
			time.Sleep(300 * time.Millisecond)
			if level, err := agentLevel(b); err == nil {
				publish("agent-attention", level)
			} else {
				fmt.Fprintln(os.Stderr, "ws: agents:", err)
			}
		case s := <-asked:
			if s == syscall.SIGUSR1 {
				refresh()
				reviews.Reset(5 * time.Minute)
			} else {
				republish()
			}
		case <-reviews.C:
			refresh()
		}
	}
}

// signalAttention sends the --watch job sig. It fails when no job is
// running, since only that job fetches the inbox.
func signalAttention(sig syscall.Signal) error {
	data, err := os.ReadFile(filepath.Join(stateDir, "attention.pid"))
	pid, _ := strconv.Atoi(strings.TrimSpace(string(data)))
	if err == nil && pid > 0 {
		err = syscall.Kill(pid, sig)
	}
	if err != nil || pid <= 0 {
		return errors.New("the attention job isn't running, so the inbox can't refresh")
	}
	return nil
}

// nextAgent is the agent a jump goes to after the one in pane last. Agents go
// in order of need, blocked, failed, done, working, then idle, and by session
// within each. A jump moves on from the last one and wraps around, except that
// an agent blocked on you or failed comes first unless the last jump went to
// one. Panes with no agent are skipped, and false means there is none.
func nextAgent(s mux.Snapshot, last string) (mux.Pane, bool) {
	agents := s.Agents()
	if len(agents) == 0 {
		return mux.Pane{}, false
	}
	slices.SortFunc(agents, func(a, b mux.Pane) int {
		return cmp.Or(cmp.Compare(a.Status, b.Status), cmp.Compare(a.Label, b.Label), cmp.Compare(a.ID, b.ID))
	})
	i := slices.IndexFunc(agents, func(p mux.Pane) bool { return p.ID == last })
	if i < 0 || (agents[0].Status <= mux.Error && agents[i].Status > mux.Error) {
		return agents[0], true
	}
	return agents[(i+1)%len(agents)], true
}

// jumpToAgent goes to the next agent, the way the agents popup does, and
// remembers it for the next jump. It works outside any terminal, as from an
// AeroSpace key, when b names the Rex app or tmux client to switch.
func jumpToAgent(b mux.Backend) error {
	s, err := b.Snapshot()
	last, _ := os.ReadFile(filepath.Join(stateDir, "last-jump"))
	next, ok := nextAgent(s, string(last))
	if !ok {
		if err != nil {
			return err
		}
		return errors.New("no agent is running")
	}
	if err := b.Show(next.Session); err != nil {
		return err
	}
	if err := b.Focus(next); err != nil {
		return err
	}
	return writeWhole("last-jump", []byte(next.ID))
}
