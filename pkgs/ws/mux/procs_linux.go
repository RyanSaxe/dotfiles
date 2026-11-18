package mux

import (
	"bytes"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// parents is each process's parent, by process ID.
func parents() (map[int]int, error) {
	dirs, err := os.ReadDir("/proc")
	parents := make(map[int]int, len(dirs))
	for _, d := range dirs {
		pid, err := strconv.Atoi(d.Name())
		if err != nil {
			continue // not a process
		}
		stat, err := os.ReadFile(filepath.Join("/proc", d.Name(), "stat"))
		if err != nil {
			continue // it exited since ReadDir
		}
		// The process's name, in parentheses, can hold spaces, so its state
		// and its parent's ID come after the last ")".
		fields := strings.Fields(string(stat[bytes.LastIndexByte(stat, ')')+1:]))
		if len(fields) > 1 {
			parents[pid], _ = strconv.Atoi(fields[1])
		}
	}
	return parents, err
}

// commandLine is a process's arguments, or nil when it has exited or is a
// kernel thread.
func commandLine(pid int) []string {
	b, err := os.ReadFile(filepath.Join("/proc", strconv.Itoa(pid), "cmdline"))
	if err != nil || len(b) == 0 {
		return nil
	}
	return strings.Split(strings.TrimSuffix(string(b), "\x00"), "\x00")
}
