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
	Agent bool `toml:"-"` // runs {agent}, so its pane is marked as the agent's
}

// Load reads dir/NAME.toml, or builtins[name] when there is no such file,
// and fills its {placeholders} from vars, each word quoted for the shell.
func Load(dir, name string, builtins map[string]string, vars map[string][]string) ([]Pane, error) {
	data, err := os.ReadFile(filepath.Join(dir, name+".toml"))
	if builtin, ok := builtins[name]; ok && errors.Is(err, os.ErrNotExist) {
		data, err = []byte(builtin), nil
	}
	var l struct{ Pane []Pane }
	if err == nil {
		var md toml.MetaData
		if md, err = toml.Decode(string(data), &l); err == nil && len(md.Undecoded()) > 0 {
			err = fmt.Errorf("unknown key %s", md.Undecoded()[0])
		}
	}
	if err == nil && len(l.Pane) == 0 {
		err = errors.New("it has no [[pane]]")
	}
	var pairs []string
	for k, words := range vars {
		pairs = append(pairs, k, Line(words))
	}
	fill := strings.NewReplacer(pairs...)
	for i := range l.Pane {
		p := &l.Pane[i]
		p.Agent, p.Run = strings.Contains(p.Run, "{agent}"), strings.TrimSpace(fill.Replace(p.Run))
		p.Split, p.Size = cmp.Or(p.Split, "right"), cmp.Or(p.Size, 50)
		if !slices.Contains([]string{"right", "left", "above", "below"}, p.Split) && err == nil {
			err = fmt.Errorf("split %q is not right, left, above or below", p.Split)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("layout %s: %w", name, err)
	}
	return l.Pane, nil
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
