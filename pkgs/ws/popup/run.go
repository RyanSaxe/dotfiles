package popup

import (
	"slices"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Run shows p until it quits, with the art that draw returns at the right of
// every header. Each reload draws it again, so the art can change while the
// popup is open, and a nil draw shows none. placeholder is the size the
// terminal reports before its real one, as WaitForSize says, and the zero
// size for a terminal that has its real size from the start.
func Run(p Popup, draw func() Art, placeholder tea.WindowSizeMsg) error {
	_, err := tea.NewProgram(WaitForSize(New(p, draw), placeholder), tea.WithAltScreen(), tea.WithMouseCellMotion()).Run()
	return err
}

// New is p as a Bubble Tea model, for a program that runs its own.
func New(p Popup, draw func() Art) tea.Model { return open(p, draw) }

// sizeWait is the longest m waits for the terminal's real size. A terminal
// whose real size is the placeholder draws m after it.
const sizeWait = 300 * time.Millisecond

// WaitForSize draws nothing of m while the terminal has placeholder, the
// size some terminals give a new pane before its real one, and draws m once
// the real size comes or sizeWait passes. m loads meanwhile. Drawing at
// once would show m at the placeholder's size for a moment, then again at
// the real size.
func WaitForSize(m tea.Model, placeholder tea.WindowSizeMsg) tea.Model {
	return sizing{Model: m, placeholder: placeholder, waiting: true}
}

type sizing struct {
	tea.Model
	placeholder tea.WindowSizeMsg
	waiting     bool
}

type sizeWaitedMsg struct{}

func (s sizing) Init() tea.Cmd {
	return tea.Batch(s.Model.Init(), tea.Tick(sizeWait, func(time.Time) tea.Msg { return sizeWaitedMsg{} }))
}

func (s sizing) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case sizeWaitedMsg:
		s.waiting = false
		return s, nil
	case tea.WindowSizeMsg:
		s.waiting = s.waiting && msg == s.placeholder
	}
	var cmd tea.Cmd
	s.Model, cmd = s.Model.Update(msg)
	return s, cmd
}

func (s sizing) View() string {
	if s.waiting {
		return ""
	}
	return s.Model.View()
}

// A stack is the popups open in one run: the first is the one Run opened,
// and each Push opens one over the last. Esc closes the top one, and
// closing the first quits.
type stack struct {
	frames []frame
	draw   func() Art
	art    Art // what draw last returned, which every frame shows
	next   int // the id the next frame gets
	size   tea.WindowSizeMsg
}

// artMsg is the art a reload drew.
type artMsg Art

func open(p Popup, draw func() Art) stack {
	var art Art
	if draw != nil {
		art = draw()
	}
	if art.Accent != "" {
		Accent = lipgloss.NewStyle().Foreground(lipgloss.Color(art.Accent))
	}
	return stack{frames: []frame{newFrame(0, false, p, art)}, draw: draw, art: art, next: 1}
}

func (s stack) Init() tea.Cmd { return s.top().load() }

func (s stack) top() frame { return s.frames[len(s.frames)-1] }

func (s stack) View() string { return s.top().view() }

func (s stack) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		return s.resizeAll(msg), nil
	case pushMsg:
		return s.pushFrame(Popup(msg))
	case closeMsg:
		return s.closeTop()
	case reloadMsg:
		return s.reloadTop(msg)
	case artMsg:
		return s.applyArt(Art(msg)), nil
	case rowsMsg:
		return s.updateFrame(msg.frame, msg)
	case detailMsg:
		return s.updateFrame(msg.frame, msg)
	case settleMsg:
		return s.updateFrame(msg.frame, msg)
	}
	return s.updateFrame(s.top().id, msg)
}

func (s stack) resizeAll(msg tea.WindowSizeMsg) stack {
	s.size, s.frames = msg, slices.Clone(s.frames)
	for i := range s.frames {
		s.frames[i], _ = s.frames[i].update(msg)
	}
	return s
}

func (s stack) pushFrame(p Popup) (stack, tea.Cmd) {
	f, _ := newFrame(s.next, true, p, s.art).update(s.size)
	s.next++
	s.frames = append(slices.Clone(s.frames), f)
	return s, f.load()
}

func (s stack) closeTop() (stack, tea.Cmd) {
	if len(s.frames) == 1 {
		return s, tea.Quit
	}
	s.frames = slices.Clone(s.frames[:len(s.frames)-1])
	if s.top().busy() {
		return s, s.top().spin.Tick
	}
	return s, nil
}

func (s stack) reloadTop(msg reloadMsg) (tea.Model, tea.Cmd) {
	m, cmd := s.updateFrame(s.top().id, msg)
	if s.draw == nil {
		return m, cmd
	}
	draw := s.draw
	return m, tea.Batch(cmd, func() tea.Msg { return artMsg(draw()) })
}

func (s stack) applyArt(art Art) stack {
	// Every frame shows the art in its header, and the header's height
	// sets the room left for the list. A new mascot brings a new accent.
	s.art, s.frames = art, slices.Clone(s.frames)
	if s.art.Accent != "" {
		Accent = lipgloss.NewStyle().Foreground(lipgloss.Color(s.art.Accent))
	}
	for i := range s.frames {
		s.frames[i].art = s.art
		s.frames[i].restyle()
		if s.size.Width > 0 {
			s.frames[i], _ = s.frames[i].update(s.size)
		}
	}
	return s
}

// updateFrame hands msg to the frame with the id, which may be under the
// top one, and drops it when that frame has closed.
func (s stack) updateFrame(id int, msg tea.Msg) (tea.Model, tea.Cmd) {
	i := slices.IndexFunc(s.frames, func(f frame) bool { return f.id == id })
	if i < 0 {
		return s, nil
	}
	s.frames = slices.Clone(s.frames)
	var cmd tea.Cmd
	s.frames[i], cmd = s.frames[i].update(msg)
	return s, cmd
}
