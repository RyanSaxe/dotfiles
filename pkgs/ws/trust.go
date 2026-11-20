package main

import (
	"bytes"
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"time"

	"github.com/BurntSushi/toml"
)

// trustFolder records root, a folder's real path, as trusted in Claude
// Code's, Codex's and Antigravity's configs, so an agent starts there
// without asking first. A CLI without a config file has never run on this
// computer, and is left alone.
func trustFolder(root string) error {
	claude := filepath.Join(cmp.Or(os.Getenv("CLAUDE_CONFIG_DIR"), home), ".claude.json")
	if err := trustInClaude(claude, root); err != nil {
		return err
	}
	codex := filepath.Join(cmp.Or(os.Getenv("CODEX_HOME"), filepath.Join(home, ".codex")), "config.toml")
	if err := trustInCodex(codex, root); err != nil {
		return err
	}
	return trustInAntigravity(antigravitySettings(), root)
}

// trustInClaude sets projects[root].hasTrustDialogAccepted in Claude Code's
// config. Running sessions rewrite that file whole, each under the lock
// that the proper-lockfile package takes, so ws takes the same lock, reads
// the file under it, and swaps the new file in, which loses no session's
// write. Only root's entry is decoded, so every other value keeps the bytes
// Claude Code wrote.
func trustInClaude(file, root string) error {
	if _, err := os.Stat(file); errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	unlock, err := lockBeside(file)
	if err != nil {
		return err
	}
	defer unlock()
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	config, err := object(data)
	if err != nil {
		return fmt.Errorf("reading %s: %w", tilde(file), err)
	}
	projects, err := object(config["projects"])
	if err != nil {
		return fmt.Errorf("reading %s's projects: %w", tilde(file), err)
	}
	project, err := object(projects[root])
	if err != nil {
		return fmt.Errorf("reading %s's entry for %s: %w", tilde(file), root, err)
	}
	project["hasTrustDialogAccepted"] = json.RawMessage("true")
	if projects[root], err = encodeJSON(project, ""); err != nil {
		return err
	}
	if config["projects"], err = encodeJSON(projects, ""); err != nil {
		return err
	}
	out, err := encodeJSON(config, "  ")
	if err != nil {
		return err
	}
	return replaceFile(file, append(out, '\n'))
}

// object decodes a JSON object with its values left as they were written,
// and an empty one from nothing or null.
func object(data json.RawMessage) (map[string]json.RawMessage, error) {
	var o map[string]json.RawMessage
	if len(data) > 0 {
		if err := json.Unmarshal(data, &o); err != nil {
			return nil, err
		}
	}
	if o == nil {
		o = map[string]json.RawMessage{}
	}
	return o, nil
}

// encodeJSON encodes v with indent, or on one line when indent is "",
// leaving <, > and & as they are, as JSON.stringify does.
func encodeJSON(v any, indent string) (json.RawMessage, error) {
	var out bytes.Buffer
	encoder := json.NewEncoder(&out)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", indent)
	err := encoder.Encode(v)
	return bytes.TrimSuffix(out.Bytes(), []byte("\n")), err
}

// trustInCodex sets projects."root".trust_level to "trusted" in Codex's
// config.toml.
func trustInCodex(file, root string) error {
	data, err := os.ReadFile(file)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	var config map[string]any
	if _, err := toml.Decode(string(data), &config); err != nil {
		return fmt.Errorf("reading %s: %w", tilde(file), err)
	}
	projects, ok := config["projects"].(map[string]any)
	if !ok {
		projects = map[string]any{}
		config["projects"] = projects
	}
	project, ok := projects[root].(map[string]any)
	if !ok {
		project = map[string]any{}
		projects[root] = project
	}
	project["trust_level"] = "trusted"
	var out bytes.Buffer
	if err := toml.NewEncoder(&out).Encode(config); err != nil {
		return err
	}
	return replaceFile(file, out.Bytes())
}

// trustInAntigravity appends root to trustedWorkspaces in Antigravity's
// settings.json, leaving every other setting as Antigravity wrote it.
func trustInAntigravity(file, root string) error {
	data, err := os.ReadFile(file)
	if errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	config, err := object(data)
	if err != nil {
		return fmt.Errorf("reading %s: %w", tilde(file), err)
	}
	var trusted []string
	if raw := config["trustedWorkspaces"]; len(raw) > 0 {
		if err := json.Unmarshal(raw, &trusted); err != nil {
			return fmt.Errorf("reading %s's trustedWorkspaces: %w", tilde(file), err)
		}
	}
	if slices.Contains(trusted, root) {
		return nil
	}
	if config["trustedWorkspaces"], err = encodeJSON(append(trusted, root), ""); err != nil {
		return err
	}
	out, err := encodeJSON(config, "  ")
	if err != nil {
		return err
	}
	return replaceFile(file, append(out, '\n'))
}

// lockBeside takes the lock proper-lockfile keeps for file: the folder
// FILE.lock, which only one process can make. Its holder touches it every
// 5 s, and proper-lockfile takes over a lock left untouched for 10 s, as
// lockBeside does.
func lockBeside(file string) (unlock func(), err error) {
	lock := file + ".lock"
	for waited := time.Duration(0); ; waited += 50 * time.Millisecond {
		err := os.Mkdir(lock, 0o755)
		if err == nil {
			return func() { os.Remove(lock) }, nil
		}
		if !errors.Is(err, fs.ErrExist) {
			return nil, err
		}
		if info, err := os.Stat(lock); err == nil && time.Since(info.ModTime()) > 10*time.Second {
			if err := os.Remove(lock); err != nil && !errors.Is(err, fs.ErrNotExist) {
				return nil, fmt.Errorf("taking over %s, which was left for %s: %w", tilde(lock), time.Since(info.ModTime()).Round(time.Second), err)
			}
			continue
		}
		if waited >= 5*time.Second {
			return nil, fmt.Errorf("%s stayed locked for 5 s, so try again", tilde(lock))
		}
		time.Sleep(50 * time.Millisecond)
	}
}
