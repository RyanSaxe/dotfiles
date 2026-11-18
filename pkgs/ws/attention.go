package main

import (
	"cmp"
	"errors"
	"fmt"
	"maps"
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
// comes from the agents that need you, the review level from the inbox, and
// the task level from the vault. The files under ~/.local/state/ws are what
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

// needRank ranks an agent that needs you, most urgent first: failed, then
// blocked, then done. tmux's bell doesn't say why it rang, so an agent that
// rang ranks with blocked.
func needRank(p mux.Pane) int {
	switch p.Status {
	case mux.Error:
		return 0
	case mux.Done:
		return 2
	}
	return 1
}

// agentLevels names each needRank as sketchybar's A shows it, then the
// level for when no agent needs you.
var agentLevels = []string{"failed", "waiting", "done", "none"}

// agentLevel is the level of the most urgent agent that needs you.
func agentLevel(s mux.Snapshot) string {
	rank := len(agentLevels) - 1
	for _, p := range s.Agents() {
		if p.NeedsYou {
			rank = min(rank, needRank(p))
		}
	}
	return agentLevels[rank]
}

// noteSeen records in seen.json the done record of the pane you're looking
// at, the landing pane of the session Rex's window shows. A record that
// finished while you looked would need you once you looked away, since the
// app asked for the pane's size before the record, and Rex.Snapshot doesn't
// count a record listed there. The file keeps only the records of panes that
// still exist, and the --watch job is its only writer.
func noteSeen(s mux.Snapshot, shown string, seen map[string]time.Time) {
	next := map[string]time.Time{}
	for _, p := range s.Panes {
		if t, ok := seen[p.ID]; ok {
			next[p.ID] = t
		}
		if shown != "" && p.Label == shown && p.Landing && p.Status == mux.Done {
			next[p.ID] = p.Updated
		}
	}
	if !maps.EqualFunc(next, seen, time.Time.Equal) {
		if err := writeJSON("seen.json", next); err != nil {
			fmt.Fprintln(os.Stderr, "ws: agents:", err)
		}
	}
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
	s, err := watched(b).Snapshot()
	if err != nil {
		return err
	}
	agents := agentLevel(s)
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

// watchAttention republishes the agent level whenever b reports a change,
// fetches the inbox every 5 minutes and rereads the vault's tasks
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
			w := watched(b)
			s, err := w.Snapshot()
			if err != nil {
				fmt.Fprintln(os.Stderr, "ws: agents:", err)
				continue
			}
			if r, ok := w.(mux.Rex); ok {
				noteSeen(s, r.Shown, r.Seen)
			}
			publish("agent-attention", agentLevel(s))
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

// nextAgent is the agent a jump goes to after the one in pane last. While any
// agent needs you, the jumps cycle through those agents alone, by needRank,
// and within each rank the one that has needed you longest first. Otherwise
// the jumps cycle through every agent, in order of need, blocked, failed,
// done, working, then idle, and by session within each. A jump goes to the agent after the last one and wraps
// around. The last one may have left the cycle, as the agent you're looking
// at does in Rex, so the jump goes on from where it would sit, and starts at
// the first when it's gone. Panes with no agent are skipped, and false means
// there is none.
func nextAgent(s mux.Snapshot, last string) (mux.Pane, bool) {
	agents := s.Agents()
	if len(agents) == 0 {
		return mux.Pane{}, false
	}
	cycle := agents
	order := func(a, b mux.Pane) int {
		return cmp.Or(cmp.Compare(a.Status, b.Status), cmp.Compare(a.Label, b.Label), cmp.Compare(a.ID, b.ID))
	}
	if waiting := slices.DeleteFunc(slices.Clone(agents), func(p mux.Pane) bool { return !p.NeedsYou }); len(waiting) > 0 {
		cycle = waiting
		order = func(a, b mux.Pane) int {
			return cmp.Or(cmp.Compare(needRank(a), needRank(b)), a.Updated.Compare(b.Updated), cmp.Compare(a.ID, b.ID))
		}
	}
	slices.SortFunc(cycle, order)
	i := slices.IndexFunc(agents, func(p mux.Pane) bool { return p.ID == last })
	if i < 0 {
		return cycle[0], true
	}
	if j := slices.IndexFunc(cycle, func(p mux.Pane) bool { return order(p, agents[i]) > 0 }); j >= 0 {
		return cycle[j], true
	}
	return cycle[0], true
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
	if err := b.Focus(next); err != nil {
		return err
	}
	return writeWhole("last-jump", []byte(next.ID))
}
