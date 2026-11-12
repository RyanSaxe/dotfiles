package popup

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/charmbracelet/x/ansi"
)

// A Screen is details that are a terminal's text, shown from their last line.
type Screen string

// Tail is the last 500 lines of a terminal capture, enough that Ctrl-U
// scrolls back past what a tall details pane shows. Blank lines at the end,
// which may still hold style sequences, are left out.
func Tail(capture string) Screen {
	lines := strings.Split(capture, "\n")
	for len(lines) > 0 && strings.TrimSpace(ansi.Strip(lines[len(lines)-1])) == "" {
		lines = lines[:len(lines)-1]
	}
	return colors(lines[max(0, len(lines)-500):])
}

// sgr matches a color and style sequence, and not a private one such as
// ESC [ > 4 m, which sets a keyboard mode. forward matches a cursor move to
// the right, which a vt capture writes in place of a run of spaces.
var sgr, forward = regexp.MustCompile(`^\x1b\[[0-9;:]*m$`), regexp.MustCompile(`^\x1b\[([0-9]*)C$`)

// colors keeps a capture's text and its color and style sequences, turns a
// move to the right into spaces, and drops every other control sequence, any
// of which could move the cursor or change a mode in the popup. A line starts
// with the styles still open from the line above, since a terminal sends a
// style only where it changes.
func colors(lines []string) Screen {
	var out, blank strings.Builder // blank holds spaces and styles until text follows them
	open := ""                     // the style sequences since the last reset
	for _, line := range lines {
		out.WriteString(open)
		var state byte
		for line != "" {
			seq, width, n, next := ansi.DecodeSequence(line, state, nil)
			switch {
			case seq == " ":
				blank.WriteString(seq)
			case width > 0 || seq == "\t":
				out.WriteString(blank.String() + seq)
				blank.Reset()
			case forward.MatchString(seq):
				cells, _ := strconv.Atoi(forward.FindStringSubmatch(seq)[1])
				blank.WriteString(strings.Repeat(" ", max(cells, 1)))
			case sgr.MatchString(seq):
				blank.WriteString(seq)
				open += seq
				if seq == "\x1b[m" || seq == "\x1b[0m" {
					open = ""
				}
			}
			line, state = line[n:], next
		}
		blank.Reset() // a line's trailing spaces would read as text cut off at the edge
		out.WriteString("\n")
	}
	return Screen(strings.TrimSuffix(out.String(), "\n"))
}
