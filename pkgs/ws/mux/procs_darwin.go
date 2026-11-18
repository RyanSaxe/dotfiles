package mux

import (
	"bytes"
	"encoding/binary"
	"strings"

	"golang.org/x/sys/unix"
)

// parents is each process's parent, by process ID.
func parents() (map[int]int, error) {
	procs, err := unix.SysctlKinfoProcSlice("kern.proc.all")
	parents := make(map[int]int, len(procs))
	for _, p := range procs {
		parents[int(p.Proc.P_pid)] = int(p.Eproc.Ppid)
	}
	return parents, err
}

// commandLine is a process's arguments, or nil when it has exited or
// belongs to another user. kern.procargs2 holds the number of arguments,
// the executable's path padded with NULs, the arguments and then the
// environment.
func commandLine(pid int) []string {
	b, err := unix.SysctlRaw("kern.procargs2", pid)
	if err != nil || len(b) < 4 {
		return nil
	}
	argc := int(binary.LittleEndian.Uint32(b))
	_, rest, _ := bytes.Cut(b[4:], []byte{0})
	args := strings.Split(strings.TrimLeft(string(rest), "\x00"), "\x00")
	return args[:min(argc, len(args))]
}
