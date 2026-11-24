package popup

import (
	"cmp"
	"time"
)

// The frame's state, each part a named type with one function that moves
// it. The frame's Update only turns Bubble Tea messages into these events.

// A tab's load. gen counts loads, so rows from a load that a reload
// replaced are dropped instead of shown over newer ones.
type loadState int

const (
	firstLoad       loadState = iota // nothing to show yet
	picking                          // nothing to show yet, and Enter waits for the rows
	loaded                           // showing rows
	failed                           // showing why the load failed
	updating                         // showing rows while a load runs, whose rows replace them
	updatingPicking                  // the same, and Enter waits for a row that matches
	reloading                        // showing the last load's rows until the next one finishes
	retrying                         // showing a failure while the next load runs
)

type tabLoad struct {
	state loadState
	gen   int
	err   error
}

type (
	tabEvent  interface{ isTabEvent() }
	reloadTab struct{}
	tabShown  struct{ gen int } // rows Load showed before it returned
	tabDone   struct {
		gen int
		err error
	}
	pickEarly struct{} // Enter, with no row to pick yet
)

func (reloadTab) isTabEvent()  {}
func (tabShown) isTabEvent()   {}
func (tabDone) isTabEvent()    {}
func (pickEarly) isTabEvent()  {}
func (keyPressed) isTabEvent() {} // any key after an early Enter takes it back

// rowsEffect is what the frame does with the rows a load brought.
type rowsEffect int

const (
	dropRows rowsEffect = iota // from a load a reload replaced, so stop reading it
	holdRows                   // keep the rows on screen, and read the load's next ones
	showRows
	showAndPick // show them, and pick the top match for the Enter that came first
)

// next moves a tab on, and says what becomes of the event's rows.
func (t tabLoad) next(e tabEvent) (tabLoad, rowsEffect) {
	switch e := e.(type) {
	case reloadTab:
		// A reload keeps the rows a finished load showed, rather than show
		// the next load's first rows, which may be only some of them.
		state := map[loadState]loadState{firstLoad: firstLoad, picking: picking, loaded: reloading, failed: retrying, updating: updating, updatingPicking: updatingPicking, reloading: reloading, retrying: retrying}[t.state]
		return tabLoad{state: state, gen: t.gen + 1, err: t.err}, dropRows
	case tabShown:
		return t.onShown(e.gen)
	case pickEarly:
		return t.onPickEarly(), dropRows
	case keyPressed:
		return t.onKeyPressed(), dropRows
	case tabDone:
		return t.onDone(e)
	}
	return t, dropRows
}

func (t tabLoad) onShown(gen int) (tabLoad, rowsEffect) {
	switch {
	case gen != t.gen:
		return t, dropRows
	case t.state == reloading:
		return t, holdRows
	case t.state == picking || t.state == updatingPicking:
		return tabLoad{state: updatingPicking, gen: t.gen}, showAndPick
	}
	return tabLoad{state: updating, gen: t.gen}, showRows
}

func (t tabLoad) onPickEarly() tabLoad {
	switch t.state {
	case firstLoad:
		return tabLoad{state: picking, gen: t.gen}
	case updating:
		return tabLoad{state: updatingPicking, gen: t.gen}
	}
	return t
}

func (t tabLoad) onKeyPressed() tabLoad {
	switch t.state {
	case picking:
		return tabLoad{state: firstLoad, gen: t.gen}
	case updatingPicking:
		return tabLoad{state: updating, gen: t.gen}
	}
	return t
}

func (t tabLoad) onDone(e tabDone) (tabLoad, rowsEffect) {
	switch {
	case e.gen != t.gen:
		return t, dropRows
	case e.err != nil:
		return tabLoad{state: failed, gen: t.gen, err: e.err}, dropRows
	case t.state == picking || t.state == updatingPicking:
		return tabLoad{state: loaded, gen: t.gen}, showAndPick
	}
	return tabLoad{state: loaded, gen: t.gen}, showRows
}

func (t tabLoad) showsRows() bool {
	return t.state == loaded || t.state == updating || t.state == updatingPicking || t.state == reloading
}
func (t tabLoad) showsErr() bool { return t.state == failed || t.state == retrying }
func (t tabLoad) busy() bool     { return t.state != loaded && t.state != failed }

// A row's details are fetched once the cursor rests on it, so holding j
// doesn't fetch every row it passes. The row under the cursor when a tab's
// final rows arrive is fetched at once. gen is the frame's reload the fetch
// belongs to, so a fetch from before a reload is dropped, and since is when
// the cursor arrived, or zero for a row it never moved to.
type detailState int

const (
	unasked  detailState = iota
	waiting              // the cursor arrived, and the frame waits to see it rest
	fetching             // the cursor rested, and the fetch runs
	shown
	missing // the fetch failed
)

type detail struct {
	state detailState
	gen   int
	since time.Time
	data  any
	err   error
}

type (
	detailEvent interface{ isDetailEvent() }
	arrived     struct { // the cursor arrived on the row
		gen int
		at  time.Time
	}
	rowsLoaded struct { // the tab's final rows arrived with the cursor on the row
		gen int
		at  time.Time // when the row's details began to wait, unless the cursor came first
	}
	rested  struct{} // the cursor is still on the row a moment later
	fetched struct {
		gen  int
		data any
		err  error
	}
)

func (arrived) isDetailEvent()    {}
func (rowsLoaded) isDetailEvent() {}
func (rested) isDetailEvent()     {}
func (fetched) isDetailEvent()    {}

// effect is what the frame does after a row's details move on.
type effect int

const (
	nothing    effect = iota
	waitToRest        // start the timer that sends rested
	fetch             // start the fetch
)

func (d detail) next(e detailEvent) (detail, effect) {
	switch e := e.(type) {
	case arrived:
		if d.state == unasked || d.state == waiting {
			return detail{state: waiting, gen: e.gen, since: e.at}, waitToRest
		}
	case rowsLoaded:
		if d.state == unasked || d.state == waiting {
			return detail{state: fetching, gen: e.gen, since: cmp.Or(d.since, e.at)}, fetch
		}
	case rested:
		if d.state == waiting {
			return detail{state: fetching, gen: d.gen, since: d.since}, fetch
		}
	case fetched:
		return d.onFetched(e), nothing
	}
	return d, nothing
}

func (d detail) onFetched(e fetched) detail {
	if d.state != fetching || e.gen != d.gen {
		return d
	}
	if e.err != nil {
		return detail{state: missing, gen: d.gen, err: e.err}
	}
	return detail{state: shown, gen: d.gen, data: e.data}
}

// Where a tab's cursor goes when its rows change. It stays on the top row,
// the best match for what was typed, until you move it, and then it stays
// on the row you moved to. Typing puts it back on the top row, since the
// best match changes.
type cursorState int

const (
	onTop    cursorState = iota // on the top row, whichever row that is
	onChosen                    // on the row you moved to, wherever it goes
)

type (
	cursorEvent   interface{ isCursorEvent() }
	movedCursor   struct{} // you moved the cursor
	changedFilter struct{} // you typed or cleared a filter
)

func (movedCursor) isCursorEvent()   {}
func (changedFilter) isCursorEvent() {}

func (c cursorState) next(e cursorEvent) cursorState {
	switch e.(type) {
	case movedCursor:
		return onChosen
	case changedFilter:
		return onTop
	}
	return c
}

// On a narrow screen such as a phone, the list and the details take turns.
// A wide screen shows both whatever this says, and keeps it for when it
// narrows again.
type phoneView int

const (
	phoneList phoneView = iota
	phoneDetails
)

type (
	phoneEvent   interface{ isPhoneEvent() }
	openDetails  struct{}
	closeDetails struct{}
)

func (openDetails) isPhoneEvent()  {}
func (closeDetails) isPhoneEvent() {}

func (v phoneView) next(e phoneEvent) phoneView {
	switch e.(type) {
	case openDetails:
		return phoneDetails
	case closeDetails:
		return phoneList
	}
	return v
}

// The footer shows the keys, a notice until the next key, or a question
// that takes the keys until it's answered or dismissed. A notice that comes
// while a question is open shows once the question closes.
type footerState int

const (
	keys footerState = iota
	notice
	asking
)

type footer struct {
	state footerState
	text  string // the notice
	q     askMsg
}

type (
	footerEvent interface{ isFooterEvent() }
	say         struct{ text string }
	ask         struct{ q askMsg }
	keyPressed  struct{}
	answer      struct{}
	dismiss     struct{}
)

func (say) isFooterEvent()        {}
func (ask) isFooterEvent()        {}
func (keyPressed) isFooterEvent() {}
func (answer) isFooterEvent()     {}
func (dismiss) isFooterEvent()    {}

// next moves the footer on, and hands back the question an answer goes to.
func (f footer) next(e footerEvent) (footer, *askMsg) {
	switch e := e.(type) {
	case say:
		return f.onSay(e.text), nil
	case ask:
		return footer{state: asking, text: f.text, q: e.q}, nil
	case keyPressed:
		if f.state == notice {
			return footer{}, nil
		}
	case answer:
		if f.state == asking {
			return f.afterQuestion(), &f.q
		}
	case dismiss:
		if f.state == asking {
			return f.afterQuestion(), nil
		}
	}
	return f, nil
}

func (f footer) onSay(text string) footer {
	if f.state == asking {
		return footer{state: asking, text: text, q: f.q}
	}
	if text == "" {
		return footer{}
	}
	return footer{state: notice, text: text}
}

func (f footer) afterQuestion() footer {
	if f.text != "" {
		return footer{state: notice, text: f.text}
	}
	return footer{}
}
