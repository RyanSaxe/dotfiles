package main

import (
	"fmt"
	"io"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

// ANSI palette indices only, so popups follow the terminal's theme.
var (
	accent, dim        = fg("4"), fg("8")
	green, red, yellow = fg("2"), fg("1"), fg("3")
	bold               = lipgloss.NewStyle().Bold(true)
	box                = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("8")).Padding(0, 1)
	stateStyles        = map[string]lipgloss.Style{"blocked": red, "error": red, "done": green, "working": fg("5"), "idle": dim, "open": accent}
)

func fg(c string) lipgloss.Style { return lipgloss.NewStyle().Foreground(lipgloss.Color(c)) }

func stateTag(state string) lipgloss.Style { return stateStyles[state].SetString(state) }

// A popup fills the frame every `ws pick` shares: a header with tabs, a
// filterable list, details for the selected row, and a footer of keys.
type popup struct {
	title, noun string
	tabs        []tab
	load        func(tab int) ([]row, error)
	fetch       func(r row) (any, error)           // details, fetched once the cursor rests on a row
	head        func(r row, d any, w int) []string // nil shows the row's meta and title
	body        func(r row, d any, w int) string   // nil shows the details as text
	follow      bool                               // the body is terminal output, so show its end
	actions     []action
}

type tab struct{ name, empty string }

type action struct {
	key, help string
	always    bool // runs with no row selected
	run       func(r row) tea.Cmd
}

// A row is two lines: prefix, title and side, then meta and tag.
type row struct {
	id, prefix, title, side, meta string
	tag                           lipgloss.Style // shown when it has a string set
	data                          any
}

// The title comes first so that filter matches inside it can be highlighted.
func (r row) FilterValue() string { return r.title + " " + r.meta }

type (
	rowsMsg struct {
		tab  int
		rows []row
		err  error
	}
	detail struct {
		id   string
		data any
		err  error
	}
	askMsg struct {
		question string
		answered func(string) tea.Cmd
	}
	settleMsg string // the cursor rested on this row long enough to fetch it
	statusMsg string
	reloadMsg string // reload every tab and show this status
	quitMsg   struct{}
)

type frame struct {
	p                 popup
	w, h, active      int
	lists             []list.Model
	loaded            []bool
	errs              []error
	loading, fetching int
	details           map[string]*detail // a nil entry is a fetch in flight
	status            string
	vp                viewport.Model
	spin              spinner.Model
	asking            *askMsg
	showDetail        bool // a narrow screen shows the details alone
	input             textinput.Model
}

func newFrame(p popup) frame {
	n := len(p.tabs)
	m := frame{p: p, lists: make([]list.Model, n), loaded: make([]bool, n), errs: make([]error, n), loading: n, details: map[string]*detail{}}
	for i := range m.lists {
		l := list.New(nil, delegate{}, 0, 0)
		l.SetShowTitle(false)
		l.SetShowFilter(false) // listPane draws the filter row
		l.SetShowStatusBar(false)
		l.SetShowHelp(false)
		l.Styles.PaginationStyle, l.Styles.ArabicPagination = lipgloss.NewStyle(), dim
		l.Paginator.ActiveDot, l.Paginator.InactiveDot = accent.Render("•"), dim.Render("•")
		l.FilterInput.Prompt, l.FilterInput.PromptStyle, l.FilterInput.Cursor.Style = "/ ", accent, accent
		m.lists[i] = l
	}
	m.vp = viewport.New(0, 0) // for its default keys, which scroll the details on a narrow screen
	m.spin = spinner.New(spinner.WithSpinner(spinner.MiniDot), spinner.WithStyle(accent))
	m.input = textinput.New()
	m.input.PromptStyle, m.input.Cursor.Style = accent, accent
	return m
}

func (m frame) Init() tea.Cmd {
	cmds := []tea.Cmd{m.spin.Tick}
	for t := range m.p.tabs {
		cmds = append(cmds, func() tea.Msg {
			rows, err := m.p.load(t)
			return rowsMsg{t, rows, err}
		})
	}
	return tea.Batch(cmds...)
}

func (m frame) selected() (row, bool) {
	r, ok := m.lists[m.active].SelectedItem().(row)
	return r, ok
}

// act runs an action off the UI thread and shows its error, if any, in the
// status line.
func act(fn func() error, after tea.Msg) tea.Cmd {
	return func() tea.Msg {
		if err := fn(); err != nil {
			return statusMsg(err.Error())
		}
		return after
	}
}

func status(s string) tea.Cmd { return func() tea.Msg { return statusMsg(s) } }

// ask asks a question in the footer and hands the answer to answered.
func ask(question string, answered func(string) tea.Cmd) tea.Cmd {
	return func() tea.Msg { return askMsg{question, answered} }
}

func (m frame) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = max(msg.Width, 40), max(msg.Height, 12) // narrower would break the layout math
		for i := range m.lists {
			m.lists[i].SetSize(m.leftW()-4, m.h-5-m.footerH())
		}
		m.syncDetail()
		return m, nil
	case rowsMsg:
		m.loading--
		m.loaded[msg.tab], m.errs[msg.tab] = true, msg.err
		items := make([]list.Item, len(msg.rows))
		for i, r := range msg.rows {
			items[i] = r
		}
		cmd := m.lists[msg.tab].SetItems(items)
		return m, tea.Batch(cmd, m.selectionChanged())
	case *detail:
		m.fetching--
		m.details[msg.id] = msg
		m.syncDetail()
		return m, nil
	case settleMsg:
		r, ok := m.selected()
		if _, seen := m.details[string(msg)]; !ok || seen || r.id != string(msg) {
			return m, nil
		}
		m.details[r.id], m.fetching = nil, m.fetching+1
		return m, tea.Batch(m.spin.Tick, func() tea.Msg {
			d, err := m.p.fetch(r)
			return &detail{r.id, d, err}
		})
	case askMsg:
		m.asking = &msg
		m.input.Reset()
		m.input.Prompt = msg.question + " "
		return m, m.input.Focus()
	case statusMsg:
		m.status = string(msg)
		return m, nil
	case reloadMsg:
		m.status, m.details, m.loading = string(msg), map[string]*detail{}, m.loading+len(m.p.tabs)
		m.syncDetail()
		return m, m.Init()
	case quitMsg:
		return m, tea.Quit
	case spinner.TickMsg:
		if m.loading+m.fetching == 0 {
			return m, nil // let the tick chain stop while idle
		}
		var cmd tea.Cmd
		m.spin, cmd = m.spin.Update(msg)
		return m, cmd
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m.updateList(msg)
}

func (m frame) handleKey(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	if a := m.asking; a != nil {
		switch k.String() {
		case "esc", "ctrl+c":
			m.asking = nil
			return m, nil
		case "enter":
			m.asking = nil
			return m, a.answered(strings.TrimSpace(m.input.Value()))
		}
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(k)
		return m, cmd
	}
	m.status = ""
	state, key := m.lists[m.active].FilterState(), k.String()
	switch {
	case state == list.Filtering:
		return m.updateList(k) // typing a filter
	case m.narrow() && m.showDetail && (key == "esc" || key == "left"):
		m.showDetail = false
		return m, nil
	case m.narrow() && !m.showDetail && (key == "i" || key == "right"):
		m.showDetail = true
		return m, nil
	case key == "esc" && state == list.FilterApplied:
		return m.updateList(k) // esc clears the filter
	}
	switch k.String() {
	case "q", "esc", "ctrl+c":
		return m, tea.Quit
	case "tab", "shift+tab":
		m.active = (m.active + 1) % len(m.lists)
		return m, m.selectionChanged()
	case "r":
		return m.Update(reloadMsg(""))
	case "ctrl+d":
		m.vp.HalfPageDown()
		return m, nil
	case "ctrl+u":
		m.vp.HalfPageUp()
		return m, nil
	}
	r, ok := m.selected()
	for _, a := range m.p.actions {
		if a.key == k.String() && (ok || a.always) {
			return m, a.run(r)
		}
	}
	if m.showDetail && m.narrow() {
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(k)
		return m, cmd
	}
	return m.updateList(k)
}

// updateList forwards a message to the active list and follows the selection.
func (m frame) updateList(msg tea.Msg) (tea.Model, tea.Cmd) {
	before, _ := m.selected()
	var cmd tea.Cmd
	m.lists[m.active], cmd = m.lists[m.active].Update(msg)
	if after, _ := m.selected(); after.id != before.id {
		cmd = tea.Batch(cmd, m.selectionChanged())
	}
	return m, cmd
}

// selectionChanged shows what is cached for the new selection and fetches the
// rest only once the cursor rests, so holding j does not start a fetch per row.
func (m *frame) selectionChanged() tea.Cmd {
	m.vp.GotoTop()
	m.syncDetail()
	r, ok := m.selected()
	if _, seen := m.details[r.id]; !ok || seen {
		return nil
	}
	return tea.Tick(150*time.Millisecond, func(time.Time) tea.Msg { return settleMsg(r.id) })
}

// Below 80 columns, as on a phone, the list and the details take turns at
// the full width and the footer wraps onto two lines.
func (m frame) narrow() bool { return m.w < 80 }

func (m frame) footerH() int {
	if m.narrow() {
		return 2
	}
	return 1
}

func (m frame) leftW() int {
	if m.narrow() {
		return m.w
	}
	return min(max(m.w*9/20, 38), 66)
}

func (m frame) rightW() int {
	if m.narrow() {
		return m.w - 4
	}
	return m.w - m.leftW() - 5
}

// fetched is the selected row's details, or nil while they load or after
// they fail.
func (m frame) fetched(r row) any {
	if d := m.details[r.id]; d != nil && d.err == nil {
		return d.data
	}
	return nil
}

// syncDetail fits the body viewport under the detail header and loads the
// selected row's body into it, one screen line per line.
func (m *frame) syncDetail() {
	r, ok := m.selected()
	w, body := m.rightW(), ""
	if d := m.fetched(r); d != nil && m.p.body != nil {
		body = m.p.body(r, d, w)
	} else if d != nil {
		body = d.(string)
	}
	lines := strings.Split(strings.ReplaceAll(body, "\t", "    "), "\n")
	for i, line := range lines {
		lines[i] = ansi.Truncate(line, w, "…")
	}
	m.vp.Width, m.vp.Height = w, max(0, m.h-3-m.footerH()-lipgloss.Height(m.detailHead(r, ok, w)))
	m.vp.SetContent(strings.Join(lines, "\n"))
	if m.p.follow {
		m.vp.GotoBottom()
	}
}

func (m frame) detailHead(r row, ok bool, w int) string {
	if !ok {
		return ""
	}
	lines := []string{ansi.Truncate(dim.Render(r.meta), w, "…"), bold.Width(w).Render(r.title), ""}
	if m.p.head != nil {
		lines = m.p.head(r, m.fetched(r), w)
	}
	if d := m.details[r.id]; d == nil {
		lines = append(lines, m.spin.View()+dim.Render(" loading details"))
	} else if d.err != nil {
		lines = append(lines, red.Width(w).Render(d.err.Error()))
	}
	rule := strings.Repeat("─", w)
	if m.vp.Height > 0 && m.vp.TotalLineCount() > m.vp.Height {
		pct := fmt.Sprintf(" %d%%", int(m.vp.ScrollPercent()*100))
		rule = strings.Repeat("─", w-len(pct)) + pct
	}
	return strings.Join(append(lines, dim.Render(rule)), "\n")
}

type delegate struct{}

func (delegate) Height() int                         { return 2 }
func (delegate) Spacing() int                        { return 1 }
func (delegate) Update(tea.Msg, *list.Model) tea.Cmd { return nil }

func (delegate) Render(w io.Writer, m list.Model, index int, item list.Item) {
	r, preW, prefix := item.(row), 0, ""
	for _, it := range m.Items() {
		if p := it.(row).prefix; p != "" {
			preW = max(preW, len(p)+1)
		}
	}
	if preW > 0 {
		prefix = fmt.Sprintf("%*s ", preW, r.prefix)
	}
	bar, pre, title := "  ", dim, lipgloss.NewStyle()
	if index == m.Index() {
		bar, pre, title = accent.Render("│ "), accent, accent.Bold(true)
	}
	tw := m.Width() - 2 - len(prefix) - 7 // bar, prefix, side column
	t := ansi.Truncate(r.title, tw, "…")
	matches := slices.DeleteFunc(slices.Clone(m.MatchesForItem(index)), func(i int) bool { return i >= len([]rune(t)) })
	line1 := bar + pre.Render(prefix) + lipgloss.StyleRunes(t, matches, title.Underline(true), title) +
		strings.Repeat(" ", tw-ansi.StringWidth(t)) + dim.Render(fmt.Sprintf(" %6s", r.side))
	tag := r.tag.String()
	meta := ansi.Truncate(r.meta, tw+6-lipgloss.Width(tag), "…")
	line2 := bar + strings.Repeat(" ", len(prefix)) + dim.Render(meta) +
		strings.Repeat(" ", max(0, tw+7-ansi.StringWidth(meta)-lipgloss.Width(tag))) + tag
	fmt.Fprint(w, line1+"\n"+line2)
}

func (m frame) View() string {
	if m.w == 0 {
		return "" // the first frame comes before the terminal size
	}
	header := " " + bold.Render(m.p.title) + dim.Render("  │ ")
	for i, t := range m.p.tabs {
		name, count := dim.Render(t.name), ""
		if m.loaded[i] && m.errs[i] == nil {
			count = " " + strconv.Itoa(len(m.lists[i].Items()))
		}
		if i == m.active {
			name = accent.Bold(true).Render(t.name)
		}
		header += " " + name + dim.Render(count) + "  "
	}
	lw, bodyH := m.leftW(), m.h-1-m.footerH()
	left := box.Width(lw - 2).Height(bodyH - 2).Render(m.listPane(lw-4, bodyH-2))
	r, ok := m.selected()
	right := box.Width(m.rightW() + 2).Height(bodyH - 2).Render(m.detailHead(r, ok, m.rightW()) + "\n" + m.vp.View())
	body := lipgloss.JoinHorizontal(lipgloss.Top, left, " ", right)
	if m.narrow() && m.showDetail {
		body = right
	} else if m.narrow() {
		body = left
	}
	return ansi.Truncate(header, m.w, "…") + "\n" + body + "\n" + m.footer()
}

func (m frame) listPane(w, h int) string {
	l := m.lists[m.active]
	center := func(lines ...string) string {
		return lipgloss.Place(w, h, lipgloss.Center, lipgloss.Center, lipgloss.JoinVertical(lipgloss.Center, lines...))
	}
	switch err := m.errs[m.active]; {
	case !m.loaded[m.active]:
		return center(m.spin.View() + dim.Render(" loading "+m.p.noun))
	case err != nil:
		return center(red.Render("Could not load "+m.p.noun), "", dim.Width(w-4).Align(lipgloss.Center).Render(err.Error()), "", dim.Render("r to retry"))
	case len(l.Items()) == 0:
		return center(green.Render("✓"), "", dim.Render(m.p.tabs[m.active].empty))
	}
	filter, count := dim.Render("/ filter"), ""
	if l.FilterState() != list.Unfiltered {
		filter = accent.Render("/ ") + l.FilterValue()
		count = dim.Render(fmt.Sprintf("%d of %d", len(l.VisibleItems()), len(l.Items())))
	}
	if l.FilterState() == list.Filtering {
		// The list pads its input to the full width, so trim it to fit the count.
		filter = ansi.Truncate(l.FilterInput.View(), w-lipgloss.Width(count)-1, "")
	}
	gap := strings.Repeat(" ", max(0, w-lipgloss.Width(filter)-lipgloss.Width(count)))
	return ansi.Truncate(filter+gap+count, w, "…") + "\n\n" + l.View()
}

func (m frame) footer() string {
	if m.asking != nil {
		return ansi.Truncate(" "+accent.Render("›")+" "+m.input.View(), m.w, "")
	}
	if m.status != "" {
		return ansi.Truncate(" "+accent.Render("›")+" "+m.status, m.w, "…")
	}
	keys := [][2]string{{"j/k", "move"}, {"tab", "switch"}, {"/", "filter"}}
	if m.narrow() && m.showDetail {
		keys = [][2]string{{"esc", "back"}, {"tab", "switch"}, {"j/k", "scroll"}}
	} else if m.narrow() {
		keys = append(keys, [2]string{"i", "details"})
	}
	if len(m.lists) == 1 {
		keys = slices.Delete(keys, 1, 2)
	}
	filterAt := slices.Index(keys, [2]string{"/", "filter"})
	for _, a := range m.p.actions {
		keys = append(keys, [2]string{strings.ReplaceAll(a.key, "ctrl+", "^"), a.help})
	}
	if m.narrow() {
		keys = append(keys, [][2]string{{"r", "refresh"}, {"q", "quit"}}...)
	} else {
		keys = append(keys, [][2]string{{"r", "refresh"}, {"^d/^u", "scroll"}, {"q", "quit"}}...)
	}
	switch m.lists[m.active].FilterState() {
	case list.Filtering:
		keys = [][2]string{{"enter", "apply"}, {"esc", "cancel"}}
	case list.FilterApplied:
		if filterAt >= 0 {
			keys[filterAt] = [2]string{"esc", "clear filter"}
		}
	}
	var parts []string
	for _, k := range keys {
		parts = append(parts, dim.Bold(true).Render(k[0])+" "+dim.Render(k[1]))
	}
	sep := dim.Render(" · ")
	if !m.narrow() {
		return ansi.Truncate(" "+strings.Join(parts, sep), m.w, "…")
	}
	fit := 1 // the keys that fit on the first line, and the rest go on the second
	for fit < len(parts) && lipgloss.Width(" "+strings.Join(parts[:fit+1], sep)) <= m.w {
		fit++
	}
	return ansi.Truncate(" "+strings.Join(parts[:fit], sep), m.w, "…") + "\n" + ansi.Truncate(" "+strings.Join(parts[fit:], sep), m.w, "…")
}
