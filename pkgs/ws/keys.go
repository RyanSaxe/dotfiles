package main

import (
	"cmp"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"workspace/mux"
	"workspace/popup"
)

// A key is one line of a key list: the keys, what they do, and where the
// binding comes from.
type key struct{ keys, does, from string }

// keysPopup lists the keys where ws runs. In Rex they are init.lua's
// bindings, then Rex's own Mac shortcuts, and in tmux the list kept by hand
// beside tmux.conf.
func keysPopup(b mux.Backend) popup.Popup {
	return popup.Popup{
		Noun: "keys", OneLine: true,
		Tabs: []popup.Tab{{Name: "Keys", Empty: "No keys."}},
		Load: func(int) ([]popup.Row, error) {
			var keys []key
			var err error
			if r, ok := b.(mux.Rex); ok {
				keys, err = rexKeys(r)
			} else {
				keys, err = tmuxKeys()
			}
			width := 0
			for _, k := range keys {
				width = max(width, utf8.RuneCountInString(k.keys))
			}
			rows := make([]popup.Row, len(keys))
			for i, k := range keys {
				rows[i] = popup.Row{ID: strconv.Itoa(i), Title: fmt.Sprintf("%-*s  %s", width, k.keys, k.does), Detail: k.from, Tag: popup.Dim.SetString(k.from)}
			}
			return rows, err
		},
	}
}

// rexKeys is init.lua's bindings, then Rex's default Mac shortcuts from
// default-keys.tsv.
func rexKeys(r mux.Rex) ([]key, error) {
	bindings, titles, err := r.Keymap()
	if err != nil {
		return nil, err
	}
	var keys []key
	for _, b := range bindings {
		// A move binding runs the Rex action in its args, and a binding to a
		// Lua function shows as client.key.forward.
		action, args := b.Action, b.Args
		if action == "move" {
			action, _ = args["action"].(string)
			args, _ = args["args"].(map[string]any)
		}
		does := cmp.Or(titles[action], action)
		if action == "client.key.forward" {
			does = "Lua function"
		}
		for _, name := range slices.Sorted(maps.Keys(args)) {
			does += fmt.Sprintf(" %s=%v", name, args[name])
		}
		keys = append(keys, key{strings.Join(b.Keys, " "), does, b.Source})
	}
	defaults, err := tsv(filepath.Join(home, ".config", "rex", "default-keys.tsv"))
	for _, f := range defaults {
		keys = append(keys, key{f[0], f[1], "Rex"})
	}
	return keys, err
}

// tmuxKeys is keys.tsv below its header: the app, the keys and what they do.
func tmuxKeys() ([]key, error) {
	lines, err := tsv(filepath.Join(home, ".config", "tmux", "keys.tsv"))
	var keys []key
	for _, f := range lines[min(1, len(lines)):] {
		keys = append(keys, key{f[1], f[2], f[0]})
	}
	return keys, err
}

// tsv is the three tab-separated fields on each line of file.
func tsv(file string) ([][]string, error) {
	data, err := os.ReadFile(file)
	var lines [][]string
	for i, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		if f := strings.Split(line, "\t"); len(f) == 3 {
			lines = append(lines, f)
		} else if err == nil {
			err = fmt.Errorf("line %d of %s has %d fields, not 3", i+1, tilde(file), len(f))
		}
	}
	return lines, err
}
