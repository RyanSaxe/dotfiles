package popup_test

import (
	"errors"
	"io"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"github.com/muesli/termenv"

	"workspace/popup"
)

var (
	enter = tea.KeyMsg{Type: tea.KeyEnter}
	esc   = tea.KeyMsg{Type: tea.KeyEsc}
	down  = tea.KeyMsg{Type: tea.KeyDown}
	up    = tea.KeyMsg{Type: tea.KeyUp}
	ctrlF = tea.KeyMsg{Type: tea.KeyCtrlF}
	ctrlR = tea.KeyMsg{Type: tea.KeyCtrlR}
	size  = tea.WindowSizeMsg{Width: 120, Height: 40}
)

// run delivers msgs to m one at a time, each once the work the last one
// started has finished, the way a person waits for a popup before the next
// key. A spinner tick is dropped, since a spinner ticks for as long as
// anything loads.
func run(m tea.Model, msgs ...tea.Msg) (tea.Model, bool) {
	quit := false
	for _, msg := range msgs {
		queue := []tea.Msg{msg}
		for len(queue) > 0 {
			msg, queue = queue[0], queue[1:]
			switch msg := msg.(type) {
			case tea.QuitMsg:
				quit = true
			case spinner.TickMsg, nil:
			case tea.BatchMsg:
				for _, cmd := range msg {
					queue = append(queue, results(cmd)...)
				}
			default:
				var cmd tea.Cmd
				m, cmd = m.Update(msg)
				queue = append(queue, results(cmd)...)
			}
		}
	}
	return m, quit
}

func results(cmd tea.Cmd) []tea.Msg {
	if cmd == nil {
		return nil
	}
	return []tea.Msg{cmd()}
}

// start opens p at a usable size and lets its first load finish.
func start(p popup.Popup) tea.Model {
	m := popup.New(p, nil)
	m, _ = run(m, size, m.Init()())
	return m
}

// picker is a popup whose Enter reports the row it picked.
func picker(rows []popup.Row, err error, picked *[]string) popup.Popup {
	return popup.Popup{
		Noun: "rows",
		Tabs: []popup.Tab{{Name: "Rows", Empty: "No rows."}},
		Load: func(int, func([]popup.Row)) ([]popup.Row, error) { return rows, err },
		Actions: []popup.Action{{Key: "enter", Help: "pick", Run: func(r popup.Row) tea.Cmd {
			*picked = append(*picked, r.ID)
			return nil
		}}},
	}
}

func TestLoadedRowsCanBePicked(t *testing.T) {
	var picked []string
	m := start(picker([]popup.Row{{ID: "a", Title: "a"}, {ID: "b", Title: "b"}}, nil, &picked))
	run(m, down, enter)
	if len(picked) != 1 || picked[0] != "b" {
		t.Errorf("picked %v, want [b]", picked)
	}
}

// A failed load offers nothing to pick, and Ctrl-R tries again.
func TestFailedLoadRetries(t *testing.T) {
	var picked []string
	rows, err := []popup.Row(nil), errors.New("gh: rate limited")
	p := picker(nil, nil, &picked)
	p.Load = func(int, func([]popup.Row)) ([]popup.Row, error) { return rows, err }
	m := start(p)
	m, _ = run(m, enter)
	if len(picked) != 0 {
		t.Fatalf("a failed load offered %v", picked)
	}
	rows, err = []popup.Row{{ID: "a", Title: "a"}}, nil
	run(m, ctrlR, enter)
	if len(picked) != 1 || picked[0] != "a" {
		t.Errorf("after a retry picked %v, want [a]", picked)
	}
}

// A failed load's message fits the list, however narrow, so the popup still
// fits its terminal.
func TestAFailedLoadFitsTheTerminal(t *testing.T) {
	p := picker(nil, errors.New("there's no inbox yet, and the job that fetches it isn't running"), new([]string))
	p.Noun, p.Fetch = "your inbox for the first time", func(popup.Row) (any, error) { return nil, nil }
	m := popup.New(p, nil)
	m, _ = run(m, tea.WindowSizeMsg{Width: 80, Height: 40}, m.Init()())
	if h := lipgloss.Height(m.View()); h > 40 {
		t.Errorf("the view is %d lines, taller than the 40-line terminal", h)
	}
}

// Rows from a load that a reload replaced never show over the newer rows,
// however late they arrive.
func TestRowsFromBeforeAReloadAreDropped(t *testing.T) {
	var picked []string
	answer := "old"
	p := picker(nil, nil, &picked)
	p.Load = func(int, func([]popup.Row)) ([]popup.Row, error) {
		return []popup.Row{{ID: answer, Title: answer}}, nil
	}
	m := popup.New(p, nil)
	first := m.Init() // the first load, still running
	answer = "new"
	m, _ = run(m, size, ctrlR)
	answer = "old"
	m, _ = run(m, first())
	run(m, enter)
	if len(picked) != 1 || picked[0] != "new" {
		t.Errorf("picked %v, want [new]", picked)
	}
}

// A refresh keeps the rows it had until the new load finishes, rather than
// the new load's first rows, which may be only some of them, and then shows
// the new load's rows.
func TestARefreshKeepsItsRowsUntilTheNewOnesArrive(t *testing.T) {
	loads, release := 0, make(chan struct{})
	p := picker(nil, nil, new([]string))
	p.Load = func(_ int, show func([]popup.Row)) ([]popup.Row, error) {
		if loads++; loads == 1 {
			return []popup.Row{{ID: "a", Title: "alpha"}, {ID: "b", Title: "bravo"}}, nil
		}
		show([]popup.Row{{ID: "a", Title: "alpha"}})
		<-release
		return []popup.Row{{ID: "a", Title: "alpha"}, {ID: "c", Title: "charlie"}}, nil
	}
	m := start(p)
	m, reload := m.Update(ctrlR)
	m, load := m.Update(reload())
	var more tea.Cmd
	for _, cmd := range load().(tea.BatchMsg) {
		if msg := cmd(); msg != nil {
			if _, tick := msg.(spinner.TickMsg); !tick {
				m, more = m.Update(msg) // the refresh's first rows
			}
		}
	}
	if view := ansi.Strip(m.View()); !strings.Contains(view, "bravo") {
		t.Errorf("while refreshing, the popup dropped bravo:\n%s", view)
	}
	close(release)
	if more == nil {
		t.Fatal("the refresh stopped reading the new load, so it never finishes")
	}
	m, _ = run(m, more())
	if view := ansi.Strip(m.View()); !strings.Contains(view, "charlie") || strings.Contains(view, "bravo") {
		t.Errorf("after the refresh, the popup shows:\n%s", view)
	}
}

// Enter pressed before the first rows arrive goes to the top match once they
// do, so typing a name and Enter straight after opening a popup works.
func TestEnterBeforeTheRowsPicksTheTopMatch(t *testing.T) {
	var picked []string
	rows := []popup.Row{{ID: "notes", Title: "notes"}, {ID: "dotfiles", Title: "dotfiles"}}
	m := popup.New(picker(rows, nil, &picked), nil)
	load := m.Init() // the first load, still running
	m, _ = run(m, size, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("dot")}, enter)
	if len(picked) != 0 {
		t.Fatalf("picked %v before any row arrived", picked)
	}
	run(m, load())
	if !slices.Equal(picked, []string{"dotfiles"}) {
		t.Errorf("picked %v, want [dotfiles]", picked)
	}
}

// Rows a Load shows appear while it still runs, and Enter picks from them.
// When the final rows replace them, the cursor stays on the row you moved it
// to, and the preview, which waits for the final rows, gets that row as Load
// returned it.
func TestRowsShownWhileLoadingGiveWayToTheFinalOnes(t *testing.T) {
	finish := make(chan struct{})
	picks, fetches := make(chan popup.Row, 4), make(chan popup.Row, 4)
	p := popup.Popup{
		Noun: "rows",
		Tabs: []popup.Tab{{Name: "Rows"}},
		Load: func(_ int, show func([]popup.Row)) ([]popup.Row, error) {
			show([]popup.Row{{ID: "a", Title: "a"}, {ID: "b", Title: "b"}})
			<-finish
			return []popup.Row{{ID: "new", Title: "new"}, {ID: "a", Title: "a"}, {ID: "b", Title: "b", Detail: "final"}}, nil
		},
		Fetch:   func(r popup.Row) (any, error) { fetches <- r; return "", nil },
		Actions: []popup.Action{{Key: "enter", Help: "pick", Run: func(r popup.Row) tea.Cmd { picks <- r; return nil }}},
	}
	// The rows arrive while the program runs, as they do in a terminal.
	prog := tea.NewProgram(popup.New(p, nil), tea.WithInput(nil), tea.WithOutput(io.Discard), tea.WithoutRenderer(), tea.WithoutSignalHandler())
	go prog.Run()
	t.Cleanup(prog.Kill)
	prog.Send(size)
	prog.Send(enter)
	if r := receive(t, picks); r.ID != "a" {
		t.Fatalf("Enter while Load ran picked %q, want a", r.ID)
	}
	prog.Send(down)
	time.Sleep(300 * time.Millisecond) // longer than the cursor rests before its preview
	close(finish)
	if r := receive(t, fetches); r.ID != "b" || r.Detail != "final" {
		t.Errorf("the first preview was of %q with detail %q, want b as Load returned it", r.ID, r.Detail)
	}
	prog.Send(enter)
	if r := receive(t, picks); r.ID != "b" {
		t.Errorf("Enter after the final rows picked %q, want b, where the cursor was", r.ID)
	}
}

// Until you move the cursor, it stays on the top row as new rows arrive, so
// Enter picks the best match. Once you move it, it stays on your row, and
// typing puts it back on the top row.
func TestTheCursorStaysOnTheTopRowUntilYouMoveIt(t *testing.T) {
	backspace := tea.KeyMsg{Type: tea.KeyBackspace}
	for _, tc := range []struct {
		name string
		keys []tea.Msg
		want string
	}{
		{"untouched", nil, "newest"},
		{"moved", []tea.Msg{down}, "bravo"},
		{"moved, then typed", []tea.Msg{down, tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("x")}, backspace}, "newest"},
	} {
		finish := make(chan struct{})
		picks := make(chan popup.Row, 4)
		p := popup.Popup{
			Noun: "rows",
			Tabs: []popup.Tab{{Name: "Rows"}},
			Load: func(_ int, show func([]popup.Row)) ([]popup.Row, error) {
				show([]popup.Row{{ID: "alpha", Title: "alpha"}, {ID: "bravo", Title: "bravo"}})
				<-finish
				return []popup.Row{{ID: "newest", Title: "newest"}, {ID: "alpha", Title: "alpha"}, {ID: "bravo", Title: "bravo"}}, nil
			},
			Actions: []popup.Action{{Key: "enter", Help: "pick", Run: func(r popup.Row) tea.Cmd { picks <- r; return nil }}},
		}
		s := new(terminal)
		prog := tea.NewProgram(popup.New(p, nil), tea.WithInput(nil), tea.WithOutput(s), tea.WithoutSignalHandler())
		go prog.Run()
		prog.Send(size)
		s.waitToDraw(t, "bravo")
		for _, k := range tc.keys {
			prog.Send(k)
		}
		close(finish)
		s.waitToDraw(t, "newest")
		prog.Send(enter)
		if r := receive(t, picks); r.ID != tc.want {
			t.Errorf("%s: Enter after the final rows picked %q, want %q", tc.name, r.ID, tc.want)
		}
		prog.Kill()
	}
}

// An Enter typed while none of the rows shown so far match waits for the
// final rows, and goes to their top match.
func TestAnEarlyEnterWaitsForARowThatMatches(t *testing.T) {
	finish := make(chan struct{})
	picks := make(chan popup.Row, 4)
	p := popup.Popup{
		Noun: "rows",
		Tabs: []popup.Tab{{Name: "Rows"}},
		Load: func(_ int, show func([]popup.Row)) ([]popup.Row, error) {
			show([]popup.Row{{ID: "a", Title: "alpha", Detail: "~/alpha"}})
			<-finish
			return []popup.Row{{ID: "a", Title: "alpha", Detail: "main"}, {ID: "b", Title: "bravo", Detail: "fix the login"}}, nil
		},
		Actions: []popup.Action{{Key: "enter", Help: "pick", Run: func(r popup.Row) tea.Cmd { picks <- r; return nil }}},
	}
	prog := tea.NewProgram(popup.New(p, nil), tea.WithInput(nil), tea.WithOutput(io.Discard), tea.WithoutRenderer(), tea.WithoutSignalHandler())
	go prog.Run()
	t.Cleanup(prog.Kill)
	prog.Send(size)
	prog.Send(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("login")})
	prog.Send(enter)
	close(finish)
	if r := receive(t, picks); r.ID != "b" {
		t.Errorf("the early Enter picked %q, want b, the final rows' match", r.ID)
	}
}

// A load and a fetch that each finish as quickly as most do draw their rows
// and details with no loading line before them, which would flash for a
// frame, even when the two together take longer than either may.
func TestAQuickLoadDrawsNoLoadingLine(t *testing.T) {
	p := picker(nil, nil, new([]string))
	p.Load = func(int, func([]popup.Row)) ([]popup.Row, error) {
		time.Sleep(250 * time.Millisecond)
		return []popup.Row{{ID: "a", Title: "a"}}, nil
	}
	p.Fetch = func(popup.Row) (any, error) { time.Sleep(200 * time.Millisecond); return "about a", nil }
	s := open(t, p)
	s.waitToDraw(t, "about a")
	for _, line := range []string{"loading rows", "loading details"} {
		if s.drew(line) {
			t.Errorf("the popup drew %q", line)
		}
	}
}

// A load or a fetch slow enough to notice says that it's loading until it
// finishes.
func TestASlowLoadSaysItsLoading(t *testing.T) {
	rows, details := make(chan struct{}), make(chan struct{})
	p := picker(nil, nil, new([]string))
	p.Load = func(int, func([]popup.Row)) ([]popup.Row, error) {
		<-rows
		return []popup.Row{{ID: "a", Title: "a"}}, nil
	}
	p.Fetch = func(popup.Row) (any, error) { <-details; return "about a", nil }
	s := open(t, p)
	s.waitToDraw(t, "loading rows")
	close(rows)
	s.waitToDraw(t, "loading details")
	close(details)
	s.waitToDraw(t, "about a")
}

// In a terminal that gives a new pane a placeholder size before its real
// one, as Rex gives 80×24, a popup draws nothing until the real size comes.
// When none comes, the placeholder was the real size, and it draws anyway.
func TestAPopupWaitsForTheTerminalsRealSize(t *testing.T) {
	placeholder := tea.WindowSizeMsg{Width: 80, Height: 24}
	p := picker([]popup.Row{{ID: "a", Title: "only-row"}}, nil, new([]string))
	start := func() (*terminal, *tea.Program) {
		s := new(terminal)
		prog := tea.NewProgram(popup.WaitForSize(popup.New(p, nil), placeholder), tea.WithInput(nil), tea.WithOutput(s), tea.WithoutSignalHandler())
		go prog.Run()
		t.Cleanup(prog.Kill)
		prog.Send(placeholder)
		return s, prog
	}

	s, prog := start()
	time.Sleep(100 * time.Millisecond)
	if s.drew("only-row") {
		t.Error("the popup drew at the placeholder size")
	}
	prog.Send(size)
	s.waitToDraw(t, "only-row")

	s, _ = start()
	s.waitToDraw(t, "only-row")
}

// open runs p as a terminal would, and keeps what it draws.
func open(t *testing.T, p popup.Popup) *terminal {
	s := new(terminal)
	prog := tea.NewProgram(popup.New(p, nil), tea.WithInput(nil), tea.WithOutput(s), tea.WithoutSignalHandler())
	go prog.Run()
	t.Cleanup(prog.Kill)
	prog.Send(size)
	return s
}

// A terminal keeps everything a running popup draws.
type terminal struct {
	mu  sync.Mutex
	out strings.Builder
}

func (s *terminal) Write(b []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.out.Write(b)
}

func (s *terminal) drew(text string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return strings.Contains(s.out.String(), text)
}

func (s *terminal) waitToDraw(t *testing.T, text string) {
	t.Helper()
	for deadline := time.Now().Add(5 * time.Second); !s.drew(text); time.Sleep(10 * time.Millisecond) {
		if time.Now().After(deadline) {
			t.Fatalf("the popup never drew %q", text)
		}
	}
}

// receive waits for what a running popup hands its Fetch or actions.
func receive(t *testing.T, c chan popup.Row) popup.Row {
	t.Helper()
	select {
	case r := <-c:
		return r
	case <-time.After(5 * time.Second):
		t.Fatal("the popup handed over no row")
	}
	return popup.Row{}
}

// A reload that leaves fewer rows than the cursor's place, as closing the
// last row's session does, puts the cursor on the new last row.
func TestAReloadThatShortensTheListKeepsARowSelected(t *testing.T) {
	var picked []string
	rows := []popup.Row{{ID: "a", Title: "a"}, {ID: "b", Title: "b"}, {ID: "c", Title: "c"}}
	p := picker(nil, nil, &picked)
	p.Load = func(int, func([]popup.Row)) ([]popup.Row, error) { return rows, nil }
	m, _ := run(start(p), down, down)
	rows = rows[:2]
	run(m, ctrlR, enter)
	if !slices.Equal(picked, []string{"b"}) {
		t.Errorf("picked %v, want [b]", picked)
	}
}

// Rows that load before the terminal's size arrives are there to pick once
// it does.
func TestRowsBeforeTheSizeCanBePicked(t *testing.T) {
	var picked []string
	m := popup.New(picker([]popup.Row{{ID: "a", Title: "a"}}, nil, &picked), nil)
	run(m, m.Init()(), size, enter)
	if !slices.Equal(picked, []string{"a"}) {
		t.Errorf("picked %v, want [a]", picked)
	}
}

// A row's details are fetched once the cursor rests on it, shown, and kept
// for when the cursor comes back.
func TestDetailsAreFetchedOnceAndShown(t *testing.T) {
	type pr struct{ title string }
	var fetches, shown []string
	p := popup.Popup{
		Noun: "rows",
		Tabs: []popup.Tab{{Name: "Rows"}},
		Load: func(int, func([]popup.Row)) ([]popup.Row, error) {
			return []popup.Row{{ID: "a", Title: "a"}, {ID: "b", Title: "b"}}, nil
		},
		Fetch: func(r popup.Row) (any, error) {
			fetches = append(fetches, r.ID)
			return pr{"details of " + r.ID}, nil
		},
		Body: func(_ popup.Row, d any, _ int) string {
			shown = append(shown, d.(pr).title)
			return ""
		},
	}
	m := start(p)
	run(m, down, up)
	if len(fetches) != 2 || fetches[0] != "a" || fetches[1] != "b" {
		t.Errorf("fetched %v, want [a b]: each row once", fetches)
	}
	if len(shown) == 0 || shown[len(shown)-1] != "details of a" {
		t.Errorf("showed %v, want the details of a last", shown)
	}
}

// press is a left click or tap on the cell where text shows, at the popup's
// last size.
func press(t *testing.T, m tea.Model, text string) tea.MouseMsg {
	t.Helper()
	for y, line := range strings.Split(ansi.Strip(m.View()), "\n") {
		if x := strings.Index(line, text); x >= 0 {
			return tea.MouseMsg{X: ansi.StringWidth(line[:x]), Y: y, Button: tea.MouseButtonLeft, Action: tea.MouseActionPress}
		}
	}
	t.Fatalf("%q is not on screen", text)
	return tea.MouseMsg{}
}

// A click or tap on a row picks it as Enter does, on a wide screen and on a
// narrow one where the list fills the pane, with rows of one line or two,
// and the wheel moves as the arrows do. A click anywhere else, such as on
// the header or beside a row in the details, picks nothing.
func TestTheMousePicksRows(t *testing.T) {
	for _, width := range []int{120, 50} {
		for _, oneLine := range []bool{false, true} {
			var picked []string
			rows := []popup.Row{{ID: "a", Title: "alpha"}, {ID: "b", Title: "beta"}, {ID: "c", Title: "gamma"}}
			p := picker(rows, nil, &picked)
			p.OneLine = oneLine
			p.Fetch = func(r popup.Row) (any, error) { return "about " + r.Title, nil }
			m := popup.New(p, nil)
			m, _ = run(m, tea.WindowSizeMsg{Width: width, Height: 40}, m.Init()())
			misses := []tea.Msg{press(t, m, "Rows")}
			if width >= 80 {
				beside := press(t, m, "beta")
				beside.X = width - 3
				misses = append(misses, beside)
			}
			m, _ = run(m, append(misses, press(t, m, "beta"))...)
			run(m, tea.MouseMsg{Button: tea.MouseButtonWheelDown}, tea.MouseMsg{Button: tea.MouseButtonWheelDown}, enter)
			if want := []string{"b", "c"}; !slices.Equal(picked, want) {
				t.Errorf("%d columns wide, one line %v, picked %v, want %v", width, oneLine, picked, want)
			}
		}
	}
}

// The tab a popup opens on loads before the others start, so their work
// can't slow down the rows on screen, even after it shows its first rows.
// The others start once it finishes, however it finishes.
func TestThePopupLoadsTheTabItOpensOnFirst(t *testing.T) {
	for _, fails := range []bool{false, true} {
		release, otherStarted := make(chan struct{}), make(chan struct{})
		p := picker(nil, nil, new([]string))
		p.Tabs = []popup.Tab{{Name: "Folders"}, {Name: "Worktrees"}}
		p.Start = 1
		p.Load = func(tab int, show func([]popup.Row)) ([]popup.Row, error) {
			if tab == 0 {
				close(otherStarted)
				return nil, nil
			}
			if fails {
				<-release
				return nil, errors.New("git failed")
			}
			show([]popup.Row{{ID: "a", Title: "a"}})
			<-release
			return []popup.Row{{ID: "a", Title: "a"}}, nil
		}
		open(t, p)
		select {
		case <-otherStarted:
			t.Fatalf("Folders started loading before Worktrees finished (Worktrees fails: %v)", fails)
		case <-time.After(100 * time.Millisecond):
		}
		close(release)
		select {
		case <-otherStarted:
		case <-time.After(5 * time.Second):
			t.Fatalf("Folders never started loading after Worktrees finished (Worktrees fails: %v)", fails)
		}
	}
}

// A popup opens on the tab it starts on, and Tab still moves to the others.
func TestAPopupOpensOnItsStartTab(t *testing.T) {
	var picked []string
	p := picker(nil, nil, &picked)
	p.Tabs = []popup.Tab{{Name: "Folders"}, {Name: "Sessions"}}
	p.Load = func(tab int, _ func([]popup.Row)) ([]popup.Row, error) {
		return []popup.Row{{ID: p.Tabs[tab].Name, Title: p.Tabs[tab].Name}}, nil
	}
	p.Start = 1
	run(start(p), enter, tea.KeyMsg{Type: tea.KeyTab}, enter)
	if want := []string{"Sessions", "Folders"}; !slices.Equal(picked, want) {
		t.Errorf("picked %v, want %v", picked, want)
	}
}

// An action's key runs it only on the tab and row its condition holds for,
// and does nothing elsewhere.
func TestAnActionRunsOnlyWhereItWorks(t *testing.T) {
	var done []string
	p := picker(nil, nil, new([]string))
	p.Tabs = []popup.Tab{{Name: "Needs you"}, {Name: "Issues"}}
	p.Load = func(int, func([]popup.Row)) ([]popup.Row, error) {
		return []popup.Row{{ID: "a", Title: "a"}, {ID: "b", Title: "b"}}, nil
	}
	p.Actions = []popup.Action{{Key: "ctrl+x", Help: "done",
		When: func(tab int, r popup.Row) bool { return tab == 0 && r.ID == "b" },
		Run:  func(r popup.Row) tea.Cmd { done = append(done, r.ID); return nil }}}
	ctrlX := tea.KeyMsg{Type: tea.KeyCtrlX}
	// Ctrl-X on each row of Needs you, then on each row of Issues.
	run(start(p), ctrlX, down, ctrlX, tea.KeyMsg{Type: tea.KeyTab}, ctrlX, down, ctrlX)
	if want := []string{"b"}; !slices.Equal(done, want) {
		t.Errorf("Ctrl-X ran on %v, want only on b in Needs you", done)
	}
}

// Shift-Tab moves through the tabs the other way, wrapping from the first
// to the last.
func TestShiftTabGoesBackThroughTheTabs(t *testing.T) {
	var picked []string
	p := picker(nil, nil, &picked)
	p.Tabs = []popup.Tab{{Name: "One"}, {Name: "Two"}, {Name: "Three"}}
	p.Load = func(tab int, _ func([]popup.Row)) ([]popup.Row, error) {
		return []popup.Row{{ID: p.Tabs[tab].Name, Title: p.Tabs[tab].Name}}, nil
	}
	shiftTab := tea.KeyMsg{Type: tea.KeyShiftTab}
	run(start(p), shiftTab, enter, shiftTab, enter)
	if want := []string{"Three", "Two"}; !slices.Equal(picked, want) {
		t.Errorf("picked %v, want %v", picked, want)
	}
}

// A reload draws the header's art again, so the popup shows art that an
// action or anything else changed, such as a new mascot, without being opened
// again.
func TestAReloadDrawsTheArtAgain(t *testing.T) {
	mascot := "raikou"
	draw := func() popup.Art { return popup.Art{Cells: mascot, Cols: len(mascot), Rows: 1} }
	p := picker([]popup.Row{{ID: "gengar", Title: "gengar"}}, nil, new([]string))
	p.Actions = []popup.Action{{Key: "enter", Help: "apply", Run: func(r popup.Row) tea.Cmd {
		return popup.Do(func() error { mascot = r.ID; return nil }, popup.Reload("switched to "+r.Title))
	}}}
	header := func(m tea.Model) string { return strings.Split(ansi.Strip(m.View()), "\n")[0] }
	m := popup.New(p, draw)
	m, _ = run(m, size, m.Init()(), enter)
	if h := header(m); !strings.Contains(h, "gengar") || strings.Contains(h, "raikou") {
		t.Errorf("after Enter changed the art, the header is %q", h)
	}
	mascot = "mew"
	if m, _ = run(m, ctrlR); !strings.Contains(header(m), "mew") {
		t.Errorf("after Ctrl-R, the header is %q", header(m))
	}
}

// The accent follows the mascot, so a reload that draws a new mascot also
// colors the popup with its accent.
func TestAReloadTakesTheNewAccent(t *testing.T) {
	profile, accent := lipgloss.ColorProfile(), popup.Accent
	lipgloss.SetColorProfile(termenv.TrueColor)
	t.Cleanup(func() { lipgloss.SetColorProfile(profile); popup.Accent = accent })
	hex := "#ff0000"
	draw := func() popup.Art { return popup.Art{Cells: "x", Cols: 1, Rows: 1, Accent: hex} }
	m := popup.New(picker([]popup.Row{{ID: "a", Title: "a"}}, nil, new([]string)), draw)
	m, _ = run(m, size, m.Init()())
	if !strings.Contains(m.View(), "38;2;255;0;0") {
		t.Fatal("the popup doesn't use the first mascot's accent")
	}
	hex = "#00ff00"
	if m, _ = run(m, ctrlR); !strings.Contains(m.View(), "38;2;0;255;0") {
		t.Error("after a reload drew a new mascot, the popup still uses the old accent")
	}
}

// Esc in a popup opened over another goes back to it, and Esc in the first
// one quits.
func TestEscReturnsToThePopupBelow(t *testing.T) {
	var picked []string
	files := picker([]popup.Row{{ID: "file", Title: "file"}}, nil, &picked)
	folders := picker([]popup.Row{{ID: "folder", Title: "folder"}}, nil, &picked)
	folders.Actions = append(folders.Actions, popup.Action{Key: "ctrl+f", Help: "files", Run: func(popup.Row) tea.Cmd { return popup.Push(files) }})
	m := start(folders)
	m, _ = run(m, ctrlF, enter, esc, enter)
	if len(picked) != 2 || picked[0] != "file" || picked[1] != "folder" {
		t.Errorf("picked %v, want [file folder]", picked)
	}
	if _, quit := run(m, esc); !quit {
		t.Error("esc in the first popup didn't quit")
	}
}
