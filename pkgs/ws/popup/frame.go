package popup

import (
	"cmp"
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

var box = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("8")).Padding(0, 1)

// The work a frame starts off the UI comes back addressed to that frame, so
// a popup opened over it never takes its rows or details.
type (
	rowsMsg struct {
		frame, tab, gen int
		rows            []Row
		err             error
	}
	detailMsg struct {
		frame, gen int
		id         string
		data       any
		err        error
	}
	settleMsg struct {
		frame int
		id    string
	}
	closeMsg struct{} // Esc with nothing left to clear
)

// A frame is one popup on screen.
type frame struct {
	id      int
	p       Popup
	w, h    int
	active  int
	reloads int // which reload the details belong to
	lists   []list.Model
	tabs    []tabLoad
	details map[string]detail
	phone   phoneView
	foot    footer
	vp      viewport.Model
	spin    spinner.Model
	input   textinput.Model
	art     Art
}

func newFrame(id int, p Popup, art Art) frame {
	m := frame{id: id, p: p, lists: make([]list.Model, len(p.Tabs)), tabs: make([]tabLoad, len(p.Tabs)), details: map[string]detail{}, art: art}
	for i := range m.lists {
		l := list.New(nil, delegate{p.OneLine}, 0, 0)
		l.Filter = listFilter
		l.SetShowTitle(false)
		l.SetShowFilter(false) // listPane draws the filter row
		l.SetShowStatusBar(false)
		l.SetShowHelp(false)
		l.Styles.PaginationStyle, l.Styles.ArabicPagination = lipgloss.NewStyle(), Dim
		l.Paginator.ActiveDot, l.Paginator.InactiveDot = Accent.Render("•"), Dim.Render("•")
		l.FilterInput.Focus() // typing edits the filter, and listPane draws it
		m.lists[i] = l
	}
	m.spin = spinner.New(spinner.WithSpinner(spinner.MiniDot), spinner.WithStyle(Accent))
	m.input = textinput.New()
	m.input.PromptStyle, m.input.Cursor.Style = Accent, Accent
	return m
}

// load starts every tab's current load.
func (m frame) load() tea.Cmd {
	cmds := []tea.Cmd{m.spin.Tick}
	for t := range m.p.Tabs {
		id, gen := m.id, m.tabs[t].gen
		cmds = append(cmds, func() tea.Msg {
			rows, err := m.p.Load(t)
			return rowsMsg{id, t, gen, rows, err}
		})
	}
	return tea.Batch(cmds...)
}

func (m frame) busy() bool {
	for _, t := range m.tabs {
		if t.busy() {
			return true
		}
	}
	for _, d := range m.details {
		if d.state == fetching {
			return true
		}
	}
	return false
}

func (m frame) selected() (Row, bool) {
	r, ok := m.lists[m.active].SelectedItem().(Row)
	return r, ok
}

func (m frame) update(msg tea.Msg) (frame, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = max(msg.Width, 40), max(msg.Height, 12) // narrower would break the layout math
		for i := range m.lists {
			m.lists[i].SetSize(m.leftW()-4, m.h-m.headerH()-4-m.footerH())
		}
		m.syncDetail()
		return m, nil
	case rowsMsg:
		var keep bool
		if m.tabs[msg.tab], keep = m.tabs[msg.tab].next(tabDone{msg.gen, msg.err}); !keep {
			return m, nil
		}
		items := make([]list.Item, len(msg.rows))
		for i, r := range msg.rows {
			items[i] = r
		}
		cmd := m.lists[msg.tab].SetItems(items)
		return m, tea.Batch(cmd, m.selectionChanged())
	case settleMsg:
		if r, ok := m.selected(); ok && r.ID == msg.id {
			return m, m.moveDetail(r, rested{})
		}
		return m, nil
	case detailMsg:
		m.details[msg.id], _ = m.details[msg.id].next(fetched{msg.gen, msg.data, msg.err})
		m.syncDetail()
		return m, nil
	case askMsg:
		m.foot, _ = m.foot.next(ask{msg})
		m.input.Reset()
		m.input.Prompt = msg.question + " "
		return m, m.input.Focus()
	case noticeMsg:
		m.foot, _ = m.foot.next(say{string(msg)})
		return m, nil
	case reloadMsg:
		m.foot, _ = m.foot.next(say{string(msg)})
		m.reloads++
		m.details = map[string]detail{}
		for i := range m.tabs {
			m.tabs[i], _ = m.tabs[i].next(reloadTab{})
		}
		m.syncDetail()
		return m, m.load()
	case quitMsg:
		return m, tea.Quit
	case spinner.TickMsg:
		if !m.busy() {
			return m, nil // let the tick chain stop while idle
		}
		var cmd tea.Cmd
		m.spin, cmd = m.spin.Update(msg)
		return m, cmd
	case tea.KeyMsg:
		return m.handleKey(msg)
	case tea.MouseMsg:
		return m.handleMouse(msg)
	}
	return m.updateList(msg)
}

// moveDetail moves the row's details on, and starts what that calls for. A
// popup with no Fetch has no details.
func (m *frame) moveDetail(r Row, e detailEvent) tea.Cmd {
	if m.p.Fetch == nil {
		return nil
	}
	d, next := m.details[r.ID].next(e)
	m.details[r.ID] = d
	id, gen := m.id, d.gen
	switch next {
	case waitToRest:
		return tea.Tick(150*time.Millisecond, func(time.Time) tea.Msg { return settleMsg{id, r.ID} })
	case fetch:
		m.syncDetail()
		return tea.Batch(m.spin.Tick, func() tea.Msg {
			data, err := m.p.Fetch(r)
			return detailMsg{id, gen, r.ID, data, err}
		})
	}
	return nil
}

func (m frame) handleKey(k tea.KeyMsg) (frame, tea.Cmd) {
	if m.foot.state == asking {
		switch k.String() {
		case "esc", "ctrl+c":
			m.foot, _ = m.foot.next(dismiss{})
			return m, nil
		case "enter":
			var q *askMsg
			m.foot, q = m.foot.next(answer{})
			return m, q.answered(strings.TrimSpace(m.input.Value()))
		}
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(k)
		return m, cmd
	}
	m.foot, _ = m.foot.next(keyPressed{})
	l, key, detailsAlone := &m.lists[m.active], k.String(), m.narrow() && m.phone == phoneDetails
	switch {
	case key == "ctrl+c":
		return m, tea.Quit
	case key == "esc" && !detailsAlone && l.FilterValue() == "":
		return m, func() tea.Msg { return closeMsg{} }
	case detailsAlone && (key == "esc" || key == "left"):
		m.phone = m.phone.next(closeDetails{})
		return m, nil
	case key == "esc":
		return m, m.filter("")
	case m.narrow() && key == "right":
		m.phone = m.phone.next(openDetails{})
		return m, nil
	}
	// A popup's own key comes first, so it can take over one of the frame's,
	// as Reviews does with Ctrl-R.
	r, ok := m.selected()
	for _, a := range m.p.Actions {
		if a.Key == key && (ok || a.Always) {
			return m, a.Run(r)
		}
	}
	switch key {
	case "up", "ctrl+k", "ctrl+p":
		l.CursorUp()
		return m, m.selectionChanged()
	case "down", "ctrl+j", "ctrl+n":
		l.CursorDown()
		return m, m.selectionChanged()
	case "tab", "shift+tab":
		m.active = (m.active + 1) % len(m.lists)
		return m, m.selectionChanged()
	case "ctrl+r":
		return m.update(reloadMsg(""))
	case "ctrl+d":
		m.vp.HalfPageDown()
		return m, nil
	case "ctrl+u":
		m.vp.HalfPageUp()
		return m, nil
	}
	// Every other key that types or deletes text edits the filter, as in fzf.
	if k.Alt || k.Type != tea.KeyRunes && k.Type != tea.KeySpace && k.Type != tea.KeyBackspace && key != "ctrl+w" {
		return m, nil
	}
	l.FilterInput, _ = l.FilterInput.Update(k)
	return m, m.filter(l.FilterInput.Value())
}

// handleMouse makes a click or tap on a row pick it as Enter does, and the
// wheel move through the list as the arrows do. The mouse does nothing else.
func (m frame) handleMouse(e tea.MouseMsg) (frame, tea.Cmd) {
	switch {
	case e.Button == tea.MouseButtonWheelUp:
		return m.handleKey(tea.KeyMsg{Type: tea.KeyUp})
	case e.Button == tea.MouseButtonWheelDown:
		return m.handleKey(tea.KeyMsg{Type: tea.KeyDown})
	case e.Button != tea.MouseButtonLeft || e.Action != tea.MouseActionPress || m.foot.state == asking:
		return m, nil
	}
	i, ok := m.rowAt(e.X, e.Y)
	if !ok {
		return m, nil
	}
	m.lists[m.active].Select(i)
	moved := m.selectionChanged()
	m, picked := m.handleKey(tea.KeyMsg{Type: tea.KeyEnter})
	return m, tea.Batch(moved, picked)
}

// rowAt is the index among the active list's shown rows of the row drawn at
// the cell x, y, if there is one.
func (m frame) rowAt(x, y int) (int, bool) {
	l, d := m.lists[m.active], delegate{m.p.OneLine}
	if !m.tabs[m.active].showsRows() || m.narrow() && m.phone == phoneDetails || x >= m.leftW() {
		return 0, false
	}
	// Rows start below the header, the box's top border, the filter row and
	// the blank line under it.
	line, step := y-m.headerH()-3, d.Height()+d.Spacing()
	start, end := l.Paginator.GetSliceBounds(len(l.VisibleItems()))
	i := start + line/step
	if line < 0 || line%step >= d.Height() || i >= end {
		return 0, false
	}
	return i, true
}

// filter shows the active list's rows that match query, or every row when
// query is empty.
func (m *frame) filter(query string) tea.Cmd {
	if l := &m.lists[m.active]; query == "" {
		l.ResetFilter()
	} else {
		l.SetFilterText(query)
	}
	return m.selectionChanged()
}

// updateList forwards a message to the active list and follows the selection.
func (m frame) updateList(msg tea.Msg) (frame, tea.Cmd) {
	before, _ := m.selected()
	var cmd tea.Cmd
	m.lists[m.active], cmd = m.lists[m.active].Update(msg)
	if after, _ := m.selected(); after.ID != before.ID {
		cmd = tea.Batch(cmd, m.selectionChanged())
	}
	return m, cmd
}

// selectionChanged shows what's known about the new selection, and tells
// its details the cursor arrived.
func (m *frame) selectionChanged() tea.Cmd {
	m.vp.GotoTop()
	m.syncDetail()
	r, ok := m.selected()
	if !ok {
		return nil
	}
	return m.moveDetail(r, arrived{m.reloads})
}

// Below 80 columns, as on a phone, the list and the details take turns at
// the full width and the footer wraps onto two lines.
func (m frame) narrow() bool { return m.w < 80 }

// sideBySide says whether the details show beside the list. A popup with no
// details is all list.
func (m frame) sideBySide() bool { return !m.narrow() && m.p.Fetch != nil }

func (m frame) footerH() int {
	if m.narrow() {
		return 2
	}
	return 1
}

// headerH is the header's height: one row, or the art's when it is drawn.
func (m frame) headerH() int { return max(1, m.art.Rows) }

func (m frame) leftW() int {
	if !m.sideBySide() {
		return m.w
	}
	// The list takes about a third unless the popup says otherwise, so the
	// details have room for a diff.
	return min(max(m.w*cmp.Or(m.p.List, 35)/100, 38), m.w-40)
}

func (m frame) rightW() int {
	if !m.sideBySide() {
		return m.w - 4
	}
	return m.w - m.leftW() - 5
}

// shown is the row's details once they arrive, or nil.
func (m frame) shown(r Row) any {
	if d := m.details[r.ID]; d.state == shown {
		return d.data
	}
	return nil
}

// syncDetail fits the body viewport under the detail header and loads the
// selected row's body into it, one screen line per line.
func (m *frame) syncDetail() {
	if m.w == 0 {
		return // rows can load before the terminal size, which syncs them when it comes
	}
	r, ok := m.selected()
	w, body := m.rightW(), ""
	switch d := m.shown(r).(type) {
	case nil:
	case Screen:
		body = string(d)
	case string:
		body = d
	default:
		body = m.p.Body(r, d, w)
	}
	lines := strings.Split(strings.ReplaceAll(body, "\t", "    "), "\n")
	for i, line := range lines {
		lines[i] = ansi.Truncate(line, w, "…") + "\x1b[m" // no style reaches past the cut or into the border
	}
	headH := 0
	if head := m.detailHead(r, ok, w); head != "" {
		headH = lipgloss.Height(head)
	}
	m.vp.Width, m.vp.Height = w, max(0, m.h-m.headerH()-2-m.footerH()-headH)
	m.vp.SetContent(strings.Join(lines, "\n"))
	if _, ok := m.shown(r).(Screen); ok {
		m.vp.GotoBottom()
	}
}

func (m frame) detailHead(r Row, ok bool, w int) string {
	if !ok {
		return ""
	}
	// A row's meta and title head its details only on a narrow screen, where
	// the list isn't beside them. A popup's own head always shows.
	var lines []string
	if m.p.Head != nil {
		lines = m.p.Head(r, m.shown(r), w)
	} else if m.narrow() {
		lines = []string{ansi.Truncate(Dim.Render(r.Detail), w, "…"), Bold.Width(w).Render(r.Title), ""}
	}
	switch d := m.details[r.ID]; {
	case m.p.Fetch == nil:
	case d.state == unasked, d.state == waiting, d.state == fetching:
		lines = append(lines, m.spin.View()+Dim.Render(" loading details"))
	case d.state == missing:
		lines = append(lines, Red.Width(w).Render(d.err.Error()))
	}
	// The rule divides a header from the body, so without one there's none.
	if len(lines) == 0 {
		return ""
	}
	rule := strings.Repeat("─", w)
	if m.vp.Height > 0 && m.vp.TotalLineCount() > m.vp.Height {
		pct := fmt.Sprintf(" %d%%", int(m.vp.ScrollPercent()*100))
		rule = strings.Repeat("─", w-len(pct)) + pct
	}
	return strings.Join(append(lines, Dim.Render(rule)), "\n")
}

// delegate draws every row of a popup the same height: two full lines, or
// one when the popup asks for it. The list can't mix heights.
type delegate struct{ oneLine bool }

func (d delegate) Height() int {
	if d.oneLine {
		return 1
	}
	return 2
}

func (delegate) Spacing() int { return 1 }

func (delegate) Update(tea.Msg, *list.Model) tea.Cmd { return nil }

func (d delegate) Render(w io.Writer, m list.Model, index int, item list.Item) {
	r, preW, prefix := item.(Row), 0, ""
	for _, it := range m.Items() {
		if p := it.(Row).Prefix; p != "" {
			preW = max(preW, len(p)+1)
		}
	}
	if preW > 0 {
		prefix = fmt.Sprintf("%*s ", preW, r.Prefix)
	}
	bar, pre, title := "  ", Dim, lipgloss.NewStyle()
	if index == m.Index() {
		bar, pre, title = Accent.Render("│ "), Accent, Accent.Bold(true)
	}
	// Title and Tag on the first line, Detail and Qualifier on the second,
	// each pair pushed to the edges.
	tag := r.Tag.String()
	if d.oneLine && r.Qualifier != "" {
		tag = strings.TrimSpace(tag + " " + Dim.Render(fmt.Sprintf("%4s", r.Qualifier)))
	}
	tw := m.Width() - 2 - len(prefix) - lipgloss.Width(tag) - 1 // bar, prefix, tag and its space
	t := ansi.Truncate(r.Title, tw, "…")
	matches := slices.DeleteFunc(slices.Clone(m.MatchesForItem(index)), func(i int) bool { return i >= len([]rune(t)) })
	line1 := bar + pre.Render(prefix) + lipgloss.StyleRunes(t, matches, title.Underline(true), title) +
		strings.Repeat(" ", tw-ansi.StringWidth(t)+1) + tag
	if d.oneLine {
		fmt.Fprint(w, line1)
		return
	}
	qualifier := Dim.Render(r.Qualifier)
	dw := m.Width() - 2 - len(prefix) - lipgloss.Width(qualifier) - 1
	detail := ansi.Truncate(r.Detail, dw, "…")
	line2 := bar + strings.Repeat(" ", len(prefix)) + Dim.Render(detail) +
		strings.Repeat(" ", dw-ansi.StringWidth(detail)+1) + qualifier
	fmt.Fprint(w, line1+"\n"+line2)
}

func (m frame) view() string {
	if m.w == 0 {
		return "" // the first frame comes before the terminal size
	}
	count := func(i int) string {
		if m.tabs[i].showsRows() {
			return " (" + strconv.Itoa(len(m.lists[i].Items())) + ")"
		}
		return ""
	}
	// The header is the tabs with their counts, and the art at the right.
	tabs := make([]string, len(m.p.Tabs))
	for i, t := range m.p.Tabs {
		style := Dim
		if i == m.active {
			style = Accent.Bold(true)
		}
		tabs[i] = style.Render(t.Name) + Dim.Render(count(i))
	}
	header := ansi.Truncate(" "+strings.Join(tabs, Dim.Render(" | ")), m.w-m.art.Cols-2, "…")
	if m.art.Rows > 0 {
		header = lipgloss.JoinHorizontal(lipgloss.Center, lipgloss.NewStyle().Width(m.w-m.art.Cols-1).Render(header), m.art.Cells)
	}
	lw, bodyH := m.leftW(), m.h-m.headerH()-m.footerH()
	left := box.Width(lw - 2).Height(bodyH - 2).Render(m.listPane(lw-4, bodyH-2))
	r, ok := m.selected()
	details := m.vp.View()
	if head := m.detailHead(r, ok, m.rightW()); head != "" {
		details = head + "\n" + details
	}
	right := box.Width(m.rightW() + 2).Height(bodyH - 2).Render(details)
	body := lipgloss.JoinHorizontal(lipgloss.Top, left, " ", right)
	if m.narrow() && m.phone == phoneDetails {
		body = right
	} else if !m.sideBySide() {
		body = left
	}
	// The image rides on the boxes' top border, a line that changes only with
	// the size, so the terminal gets it again only after a resize repaints.
	return header + "\n" + m.art.Setup + body + "\n" + m.renderFooter()
}

func (m frame) listPane(w, h int) string {
	l, t := m.lists[m.active], m.tabs[m.active]
	center := func(lines ...string) string {
		for i, line := range lines {
			lines[i] = lipgloss.NewStyle().Width(w).Align(lipgloss.Center).Render(line) // a line wider than the list would widen every line
		}
		return lipgloss.Place(w, h, lipgloss.Center, lipgloss.Center, lipgloss.JoinVertical(lipgloss.Center, lines...))
	}
	switch {
	case t.state == firstLoad:
		return center(m.spin.View() + Dim.Render(" loading "+m.p.Noun))
	case t.showsErr():
		return center(Red.Render("Could not load "+m.p.Noun), "", Dim.Width(w-4).Align(lipgloss.Center).Render(t.err.Error()), "", Dim.Render("^r to retry"))
	case len(l.Items()) == 0:
		return center(Green.Render("✓"), "", Dim.Render(m.p.Tabs[m.active].Empty))
	}
	filter, count := Dim.Render("/ type to filter"), ""
	if query := l.FilterValue(); query != "" {
		filter = Accent.Render("/ ") + query
		count = Dim.Render(fmt.Sprintf("%d of %d", len(l.VisibleItems()), len(l.Items())))
	}
	gap := strings.Repeat(" ", max(0, w-lipgloss.Width(filter)-lipgloss.Width(count)))
	return ansi.Truncate(filter+gap+count, w, "…") + "\n\n" + l.View()
}

func (m frame) renderFooter() string {
	switch m.foot.state {
	case asking:
		return ansi.Truncate(" "+Accent.Render("›")+" "+m.input.View(), m.w, "")
	case notice:
		return ansi.Truncate(" "+Accent.Render("›")+" "+m.foot.text, m.w, "…")
	}
	esc := "quit"
	if m.lists[m.active].FilterValue() != "" {
		esc = "clear"
	}
	detailsAlone := m.narrow() && m.phone == phoneDetails
	keys := [][2]string{{"↑↓", "move"}, {"tab", "switch"}}
	if detailsAlone {
		keys, esc = [][2]string{{"esc", "back"}, {"↑↓", "move"}, {"tab", "switch"}}, ""
	} else if m.narrow() {
		keys = append(keys, [2]string{"→", "details"})
	}
	if len(m.lists) == 1 {
		keys = slices.DeleteFunc(keys, func(k [2]string) bool { return k[0] == "tab" })
	}
	for _, a := range m.p.Actions {
		keys = append(keys, [2]string{strings.ReplaceAll(a.Key, "ctrl+", "^"), a.Help})
	}
	if !slices.ContainsFunc(m.p.Actions, func(a Action) bool { return a.Key == "ctrl+r" }) {
		keys = append(keys, [2]string{"^r", "refresh"})
	}
	if m.sideBySide() || detailsAlone {
		keys = append(keys, [2]string{"^d/^u", "scroll"})
	}
	if esc != "" {
		keys = append(keys, [2]string{"esc", esc})
	}
	var parts []string
	for _, k := range keys {
		parts = append(parts, Dim.Bold(true).Render(k[0])+" "+Dim.Render(k[1]))
	}
	sep := Dim.Render(" · ")
	if !m.narrow() {
		return ansi.Truncate(" "+strings.Join(parts, sep), m.w, "…")
	}
	fit := 1 // the keys that fit on the first line, and the rest go on the second
	for fit < len(parts) && lipgloss.Width(" "+strings.Join(parts[:fit+1], sep)) <= m.w {
		fit++
	}
	return ansi.Truncate(" "+strings.Join(parts[:fit], sep), m.w, "…") + "\n" + ansi.Truncate(" "+strings.Join(parts[fit:], sep), m.w, "…")
}
