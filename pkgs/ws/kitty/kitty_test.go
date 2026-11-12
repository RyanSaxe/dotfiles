package kitty_test

import (
	"strings"
	"testing"

	"github.com/charmbracelet/x/ansi"

	"workspace/kitty"
)

// Lip Gloss and Bubble Tea measure every line with x/ansi, so if it counted a
// placeholder cell, a character with two diacritics, as anything but one
// column, each border and pad beside an image would shift.
func TestPlaceholderCellIsOneColumn(t *testing.T) {
	for _, line := range strings.Split(kitty.Placeholders(0x575301, 7, 3), "\n") {
		if w := ansi.StringWidth(line); w != 7 {
			t.Errorf("a row of 7 placeholder cells measures %d columns", w)
		}
	}
}
