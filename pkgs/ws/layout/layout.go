// Package layout reads session layouts: the panes a new session opens with
// and the commands typed into them.
package layout

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/BurntSushi/toml"
)

// A Pane is one terminal of a layout. Each pane after the first splits the
// one before it, taking Size percent of the space.
type Pane struct {
	Run   string
	Split string // right, left, above or below
	Size  int
	Focus bool
}

// Load reads dir/NAME.toml, or builtins[name] when there is no such file,
// and fills its {placeholders} from vars, each word quoted for the shell.
func Load(dir, name string, builtins map[string]string, vars map[string][]string) ([]Pane, error) {
	panes, err := readLayout(dir, name, builtins)
	if err == nil {
		err = fillPanes(panes, vars)
	}
	if err != nil {
		return nil, fmt.Errorf("layout %s: %w", name, err)
	}
	return panes, nil
}

func readLayout(dir, name string, builtins map[string]string) ([]Pane, error) {
	data, err := os.ReadFile(filepath.Join(dir, name+".toml")) //nolint:gosec // reads local layout file from configured layouts dir
	if builtin, ok := builtins[name]; ok && errors.Is(err, os.ErrNotExist) {
		data, err = []byte(builtin), nil
	}
	if err != nil {
		return nil, err
	}
	var l struct{ Pane []Pane }
	md, err := toml.Decode(string(data), &l)
	if err != nil {
		return nil, err
	}
	if len(md.Undecoded()) > 0 {
		return nil, fmt.Errorf("unknown key %s", md.Undecoded()[0])
	}
	if len(l.Pane) == 0 {
		return nil, errors.New("it has no [[pane]]")
	}
	return l.Pane, nil
}

func fillPanes(panes []Pane, vars map[string][]string) error {
	var pairs []string
	for k, words := range vars {
		pairs = append(pairs, k, Line(words))
	}
	fill := strings.NewReplacer(pairs...)
	for i := range panes {
		p := &panes[i]
		p.Run = strings.TrimSpace(fill.Replace(p.Run))
		p.Split, p.Size = cmp.Or(p.Split, "right"), cmp.Or(p.Size, 50)
		if !slices.Contains([]string{"right", "left", "above", "below"}, p.Split) {
			return fmt.Errorf("split %q is not right, left, above or below", p.Split)
		}
	}
	return nil
}

// Line is words as one line the shell reads back as those words.
func Line(words []string) string {
	quoted := make([]string, len(words))
	for i, w := range words {
		quoted[i] = Quote(w)
	}
	return strings.Join(quoted, " ")
}

// Quote makes a word safe to type into the shell, leaving plain words bare
// so the typed command reads the way a person would type it.
func Quote(s string) string {
	if s != "" && strings.Trim(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@%+,") == "" {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}
