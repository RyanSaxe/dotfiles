package mux

import (
	"path/filepath"
	"slices"
	"strings"
)

// A processTree is each process's children, by the parent's process ID.
// It's read from the system rather than from ps, which takes about 20 ms
// where the system takes about a tenth of one.
type processTree map[int][]int

func readProcessTree() (processTree, error) {
	parents, err := parents()
	tree := processTree{}
	for pid, parent := range parents {
		if pid != parent { // macOS lists process 0 as its own parent
			tree[parent] = append(tree[parent], pid)
		}
	}
	return tree, err
}

// runsAgent says whether the process pid, or any process under it, is an
// agent CLI. It starts at pid itself, since a pane can run its command
// with no shell, as pair spawn does.
func (t processTree) runsAgent(pid int) bool {
	for todo := []int{pid}; len(todo) > 0; todo = todo[1:] {
		if isAgent(commandLine(todo[0])) {
			return true
		}
		todo = append(todo, t[todo[0]]...)
	}
	return false
}

// agentCLIs are the names agent CLIs run as.
var agentCLIs = []string{"claude", "codex", "agy", "pi"}

// isAgent says whether a command line runs an agent CLI. Copilot CLI runs
// as node, with the script from the folder nixpkgs installs it in. Neovim's
// Copilot language server is a node script too, from another folder.
func isAgent(args []string) bool {
	if len(args) == 0 {
		return false
	}
	name := filepath.Base(args[0])
	return slices.Contains(agentCLIs, name) ||
		name == "node" && len(args) > 1 && strings.Contains(args[1], "/github-copilot-cli/")
}
