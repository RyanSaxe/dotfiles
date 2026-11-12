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

// Attention is what sketchybar's A and R letters show. The agent level comes
// from Rex's statuses, and the review level from the inbox. The files under
// ~/.local/state/ws are what --watch last published, for sketchybar and
// Reviews to read.

// agentLevel is waiting when a program is blocked on you or failed, and none
// otherwise. A finished agent doesn't count: Rex doesn't tell ws when you've
// looked at one, so it would stay lit until the agent ran again.
func agentLevel() (string, error) {
	ts, err := mux.Rex{}.Terminals()
	for _, t := range ts {
		if t.Status <= mux.Error {
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

func attention(watch, jump bool, client string) error {
	switch {
	case watch:
		return watchAttention()
	case jump:
		return jumpToAgent(client)
	}
	agents, err := agentLevel()
	if err != nil {
		return err
	}
	var in inbox
	var a acks
	readJSON("inbox.json", &in)
	readJSON("acknowledged.json", &a)
	fmt.Println(agents, reviewLevel(in, a))
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

// watchAttention republishes the agent level whenever Rex reports a status
// change, and fetches the inbox every 5 minutes. It is the only process that
// fetches the inbox. SIGUSR1 asks it to fetch now, as Ctrl-R in Reviews does,
// and SIGUSR2 to republish the review level, after an acknowledgement. It
// runs until it is killed.
func watchAttention() error {
	if err := writeWhole("attention.pid", []byte(strconv.Itoa(os.Getpid()))); err != nil {
		return err
	}
	// A signal already waiting covers any more, since one recount sees both.
	changed := make(chan struct{}, 1)
	go mux.Rex{}.Follow(func() {
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
		next, err := fetchInbox(in, watchList(), time.Now())
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
	reviews := time.NewTicker(5 * time.Minute)
	refresh()
	for {
		select {
		case <-changed:
			// A burst of reports, such as an agent finishing, settles first.
			time.Sleep(300 * time.Millisecond)
			if level, err := agentLevel(); err == nil {
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

// nextAgent is the agent a jump goes to after the one at block last. Agents go
// in order of need, blocked, failed, done, working, then idle, and by session
// within each. A jump moves on from the last one and wraps around, except that
// an agent blocked on you or failed comes first unless the last jump went to
// one. Terminals with no agent are skipped, and false means there is none.
func nextAgent(ts []mux.Terminal, last string) (mux.Terminal, bool) {
	agents := slices.DeleteFunc(slices.Clone(ts), func(t mux.Terminal) bool { return t.Status == mux.Open })
	if len(agents) == 0 {
		return mux.Terminal{}, false
	}
	slices.SortFunc(agents, func(a, b mux.Terminal) int {
		return cmp.Or(cmp.Compare(a.Status, b.Status), cmp.Compare(a.Label, b.Label), cmp.Compare(a.Block, b.Block))
	})
	i := slices.IndexFunc(agents, func(t mux.Terminal) bool { return t.Block == last })
	if i < 0 || (agents[0].Status <= mux.Error && agents[i].Status > mux.Error) {
		return agents[0], true
	}
	return agents[(i+1)%len(agents)], true
}

// jumpToAgent brings the Rex app to the next agent, the way the agents popup
// does, and remembers it for the next jump. It works outside any terminal, as
// from an AeroSpace key, because it names the app client itself.
func jumpToAgent(client string) error {
	ts, err := mux.Rex{}.Terminals()
	last, _ := os.ReadFile(filepath.Join(stateDir, "last-jump"))
	next, ok := nextAgent(ts, string(last))
	if !ok {
		if err != nil {
			return err
		}
		return errors.New("no agent is running")
	}
	if client == "" {
		if client, err = (mux.Rex{}).App(); err != nil {
			return err
		}
	}
	rex := mux.Rex{Client: client}
	if err := rex.Show(next.Session); err != nil {
		return err
	}
	if err := rex.Focus(next.Session, next.Block); err != nil {
		return err
	}
	return writeWhole("last-jump", []byte(next.Block))
}
