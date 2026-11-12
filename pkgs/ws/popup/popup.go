// Package popup is the frame every popup shares: a header of tabs, a list
// filtered the way fzf filters, the selected row's details, and a footer of
// keys. A popup is a Popup value, and the frame does the rest.
package popup

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// A Popup is one list to pick from: its tabs, how a tab loads, what a row's
// details show, and its keys. Load and Fetch run off the UI.
type Popup struct {
	Noun    string
	OneLine bool // rows of one line, with the title, tag and qualifier on it
	List    int  // the list's share of the width in percent, 35 when unset // what it lists, as in "loading folders"
	Tabs    []Tab
	Load    func(tab int) ([]Row, error)
	Fetch   func(r Row) (any, error)                 // details, once the cursor rests on a row, or nil for none and a list the full width
	Head    func(r Row, details any, w int) []string // nil shows the row's meta and title on a phone
	Body    func(r Row, details any, w int) string   // draws details that aren't a string or a Screen
	Actions []Action
}

type Tab struct{ Name, Empty string }

type Action struct {
	Key, Help string
	Always    bool // runs with no row selected
	Run       func(r Row) tea.Cmd
}

// A Row is up to two lines: prefix, title, tag and side, then meta.
//
// It has four places: Title and Tag on its first line, Detail and Qualifier
// on its second. A popup fills the ones it has something for, and the frame
// lays them out the same way in every popup.
type Row struct {
	ID, Prefix               string
	Title, Detail, Qualifier string
	Tag                      lipgloss.Style // shown when it has a string set
	Data                     any
}

// FilterValue puts the title first, so matches inside it can be highlighted.
func (r Row) FilterValue() string { return r.Title + " " + r.Detail }

// Art sits at the right of the header, such as a mascot: Kitty placeholder
// Cells, and the Setup the terminal needs before it can draw them.
type Art struct {
	Cells, Setup string
	Cols, Rows   int
}

// The terminal's own palette, so popups follow its theme.
var (
	Accent, Dim        = Fg("4"), Fg("8")
	Green, Red, Yellow = Fg("2"), Fg("1"), Fg("3")
	Bold               = lipgloss.NewStyle().Bold(true)
)

// Fg is a style in one of the terminal's 16 colors, by its number.
func Fg(c string) lipgloss.Style { return lipgloss.NewStyle().Foreground(lipgloss.Color(c)) }

// What an action's command can return to the frame.
type (
	noticeMsg string
	reloadMsg string
	quitMsg   struct{}
	pushMsg   Popup
	askMsg    struct {
		question string
		answered func(string) tea.Cmd
	}
)

// Notice shows text in the footer until the next key.
func Notice(text string) tea.Msg { return noticeMsg(text) }

// Reload loads every tab again and shows notice.
func Reload(notice string) tea.Msg { return reloadMsg(notice) }

// Quit closes the popup and every popup it was opened over.
var Quit tea.Msg = quitMsg{}

// Do runs work off the UI, then hands the frame then, or work's error as a
// notice.
func Do(work func() error, then tea.Msg) tea.Cmd {
	return func() tea.Msg {
		if err := work(); err != nil {
			return noticeMsg(err.Error())
		}
		return then
	}
}

// Say shows notice in the footer until the next key.
func Say(notice string) tea.Cmd { return func() tea.Msg { return noticeMsg(notice) } }

// Ask asks a question in the footer and hands the answer to answered.
func Ask(question string, answered func(string) tea.Cmd) tea.Cmd {
	return func() tea.Msg { return askMsg{question, answered} }
}

// Push opens p over this popup. Esc in p comes back here.
func Push(p Popup) tea.Cmd { return func() tea.Msg { return pushMsg(p) } }
