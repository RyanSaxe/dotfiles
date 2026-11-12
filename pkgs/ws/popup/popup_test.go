package popup_test

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"

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
	m := popup.New(p, popup.Art{})
	m, _ = run(m, size, m.Init()())
	return m
}

// picker is a popup whose Enter reports the row it picked.
func picker(rows []popup.Row, err error, picked *[]string) popup.Popup {
	return popup.Popup{
		Noun: "rows",
		Tabs: []popup.Tab{{Name: "Rows", Empty: "No rows."}},
		Load: func(int) ([]popup.Row, error) { return rows, err },
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
	p.Load = func(int) ([]popup.Row, error) { return rows, err }
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
	m := popup.New(p, popup.Art{})
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
	p.Load = func(int) ([]popup.Row, error) { return []popup.Row{{ID: answer, Title: answer}}, nil }
	m := popup.New(p, popup.Art{})
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

// Rows that load before the terminal's size arrives are there to pick once
// it does.
func TestRowsBeforeTheSizeCanBePicked(t *testing.T) {
	var picked []string
	m := popup.New(picker([]popup.Row{{ID: "a", Title: "a"}}, nil, &picked), popup.Art{})
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
		Load: func(int) ([]popup.Row, error) { return []popup.Row{{ID: "a", Title: "a"}, {ID: "b", Title: "b"}}, nil },
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
			m := popup.New(p, popup.Art{})
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
