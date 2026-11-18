package main

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/BurntSushi/toml"
)

// configDir holds what ws reads as settings: config.toml, which the home
// switch writes from the host file, layouts and bookmarks. XDG_CONFIG_HOME
// moves it, so a scratch run can use its own.
var configDir = filepath.Join(cmp.Or(os.Getenv("XDG_CONFIG_HOME"), filepath.Join(home, ".config")), "ws")

// A config is what the host file sets for ws: the agent CLI it starts, and
// whether it opens a worktree as a tab of its project's session or as a
// session of its own.
type config struct {
	Agent  string `toml:"agent"`
	OpenAs string `toml:"open_as"`
}

func loadConfig() (config, error) {
	var c config
	path := filepath.Join(configDir, "config.toml")
	if _, err := toml.DecodeFile(path, &c); err != nil {
		return c, fmt.Errorf("reading ws's config, which home-switch writes: %w", err)
	}
	if !slices.Contains(agents, c.Agent) {
		return c, fmt.Errorf("%s names the agent %q, and ws starts only %s", path, c.Agent, strings.Join(agents, " and "))
	}
	if c.OpenAs != "tab" && c.OpenAs != "session" {
		return c, fmt.Errorf("%s says open_as %q, which is neither tab nor session", path, c.OpenAs)
	}
	return c, nil
}

// agents are the programs ws starts as an agent.
var agents = []string{"claude", "codex"}

// defaultAgent is the agent the config names, which ws starts when a
// command names none.
func defaultAgent() (string, error) {
	c, err := loadConfig()
	return c.Agent, err
}

// agentCommand is the words that start agent, or the default agent when
// agent is "", with flags after it. Without flags, the agent's own settings
// give its model and effort.
func agentCommand(agent string, flags []string) ([]string, error) {
	if agent == "" {
		var err error
		if agent, err = defaultAgent(); err != nil {
			return nil, err
		}
	}
	return append([]string{agent}, flags...), nil
}

// agentSettings is the model and effort an agent's own settings give it,
// "" for each one they leave unset: claude's in ~/.claude/settings.json and
// codex's in ~/.codex/config.toml. CLAUDE_CONFIG_DIR and CODEX_HOME move
// them, as they do for the agents.
func agentSettings(agent string) (model, effort string, err error) {
	switch agent {
	case "claude":
		var s struct {
			Model       string `json:"model"`
			EffortLevel string `json:"effortLevel"`
		}
		var data []byte
		data, err = os.ReadFile(filepath.Join(cmp.Or(os.Getenv("CLAUDE_CONFIG_DIR"), filepath.Join(home, ".claude")), "settings.json"))
		if err == nil {
			err = json.Unmarshal(data, &s)
		}
		model, effort = s.Model, s.EffortLevel
	case "codex":
		var s struct {
			Model  string `toml:"model"`
			Effort string `toml:"model_reasoning_effort"`
		}
		_, err = toml.DecodeFile(filepath.Join(cmp.Or(os.Getenv("CODEX_HOME"), filepath.Join(home, ".codex")), "config.toml"), &s)
		model, effort = s.Model, s.Effort
	}
	if errors.Is(err, os.ErrNotExist) {
		err = nil
	}
	return model, effort, err
}

// printAgent prints the agent ws starts, then the model and effort its own
// settings give it.
func printAgent() error {
	agent, err := defaultAgent()
	if err != nil {
		return err
	}
	model, effort, err := agentSettings(agent)
	if err != nil {
		return err
	}
	for _, line := range [][2]string{{"agent", agent}, {"model", model}, {"effort", effort}} {
		fmt.Printf("%-8s%s\n", line[0], cmp.Or(line[1], "not set"))
	}
	return nil
}
