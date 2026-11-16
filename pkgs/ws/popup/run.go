package popup

import (
	"slices"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Run shows p until it quits, with the art that draw returns at the right of
// every header. Each reload draws it again, so the art can change while the
// popup is open, and a nil draw shows none.
func Run(p Popup, draw func() Art) error {
	_, err := tea.NewProgram(New(p, draw), tea.WithAltScreen(), tea.WithMouseCellMotion()).Run()
	return err
}

// New is p as a Bubble Tea model, for a program that runs its own.
func New(p Popup, draw func() Art) tea.Model { return open(p, draw) }

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
	return stack{frames: []frame{newFrame(0, p, art)}, draw: draw, art: art, next: 1}
}

func (s stack) Init() tea.Cmd { return s.top().load() }

func (s stack) top() frame { return s.frames[len(s.frames)-1] }

func (s stack) View() string { return s.top().view() }

func (s stack) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		s.size, s.frames = msg, slices.Clone(s.frames)
		for i := range s.frames {
			s.frames[i], _ = s.frames[i].update(msg)
		}
		return s, nil
	case pushMsg:
		f, _ := newFrame(s.next, Popup(msg), s.art).update(s.size)
		s.next++
		s.frames = append(slices.Clone(s.frames), f)
		return s, f.load()
	case closeMsg:
		if len(s.frames) == 1 {
			return s, tea.Quit
		}
		s.frames = slices.Clone(s.frames[:len(s.frames)-1])
		if s.top().busy() {
			return s, s.top().spin.Tick
		}
		return s, nil
	case reloadMsg:
		m, cmd := s.updateFrame(s.top().id, msg)
		if s.draw == nil {
			return m, cmd
		}
		draw := s.draw
		return m, tea.Batch(cmd, func() tea.Msg { return artMsg(draw()) })
	case artMsg:
		// Every frame shows the art in its header, and the header's height
		// sets the room left for the list. A new mascot brings a new accent.
		s.art, s.frames = Art(msg), slices.Clone(s.frames)
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
		return s, nil
	case rowsMsg:
		return s.updateFrame(msg.frame, msg)
	case detailMsg:
		return s.updateFrame(msg.frame, msg)
	case settleMsg:
		return s.updateFrame(msg.frame, msg)
	}
	return s.updateFrame(s.top().id, msg)
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
