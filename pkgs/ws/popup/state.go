package popup

// The frame's state, each part a named type with one function that moves
// it. The frame's Update only turns Bubble Tea messages into these events.

// A tab's load. gen counts loads, so rows from a load that a reload
// replaced are dropped instead of shown over newer ones.
type loadState int

const (
	firstLoad loadState = iota // nothing to show yet
	loaded                     // showing rows
	failed                     // showing why the load failed
	reloading                  // showing rows while the next load runs
	retrying                   // showing a failure while the next load runs
)

type tabLoad struct {
	state loadState
	gen   int
	err   error
}

type (
	tabEvent  interface{ isTabEvent() }
	reloadTab struct{}
	tabDone   struct {
		gen int
		err error
	}
)

func (reloadTab) isTabEvent() {}
func (tabDone) isTabEvent()   {}

// next moves a tab on, and says whether the event's rows go into the list.
func (t tabLoad) next(e tabEvent) (tabLoad, bool) {
	switch e := e.(type) {
	case reloadTab:
		state := map[loadState]loadState{firstLoad: firstLoad, loaded: reloading, failed: retrying, reloading: reloading, retrying: retrying}[t.state]
		return tabLoad{state: state, gen: t.gen + 1, err: t.err}, false
	case tabDone:
		switch {
		case e.gen != t.gen:
			return t, false
		case e.err != nil:
			return tabLoad{state: failed, gen: t.gen, err: e.err}, false
		}
		return tabLoad{state: loaded, gen: t.gen}, true
	}
	return t, false
}

func (t tabLoad) showsRows() bool { return t.state == loaded || t.state == reloading }
func (t tabLoad) showsErr() bool  { return t.state == failed || t.state == retrying }
func (t tabLoad) busy() bool      { return t.state != loaded && t.state != failed }

// A row's details are fetched once the cursor rests on it, so holding j
// doesn't fetch every row it passes. gen is the frame's reload the fetch
// belongs to, so a fetch from before a reload is dropped.
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
	data  any
	err   error
}

type (
	detailEvent interface{ isDetailEvent() }
	arrived     struct{ gen int } // the cursor arrived on the row
	rested      struct{}          // the cursor is still on the row a moment later
	fetched     struct {
		gen  int
		data any
		err  error
	}
)

func (arrived) isDetailEvent() {}
func (rested) isDetailEvent()  {}
func (fetched) isDetailEvent() {}

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
			return detail{state: waiting, gen: e.gen}, waitToRest
		}
	case rested:
		if d.state == waiting {
			return detail{state: fetching, gen: d.gen}, fetch
		}
	case fetched:
		switch {
		case d.state != fetching || e.gen != d.gen:
			return d, nothing
		case e.err != nil:
			return detail{state: missing, gen: d.gen, err: e.err}, nothing
		}
		return detail{state: shown, gen: d.gen, data: e.data}, nothing
	}
	return d, nothing
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
	after := func() footer { // what shows once a question closes
		if f.text != "" {
			return footer{state: notice, text: f.text}
		}
		return footer{}
	}
	switch e := e.(type) {
	case say:
		switch {
		case f.state == asking:
			return footer{state: asking, text: e.text, q: f.q}, nil
		case e.text == "":
			return footer{}, nil
		}
		return footer{state: notice, text: e.text}, nil
	case ask:
		return footer{state: asking, text: f.text, q: e.q}, nil
	case keyPressed:
		if f.state == notice {
			return footer{}, nil
		}
	case answer:
		if f.state == asking {
			return after(), &f.q
		}
	case dismiss:
		if f.state == asking {
			return after(), nil
		}
	}
	return f, nil
}
