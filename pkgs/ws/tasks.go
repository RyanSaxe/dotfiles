package main

import (
	"cmp"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"workspace/kitty"
	"workspace/markdown"
	"workspace/mux"
	"workspace/popup"
)

// A task is a `- [ ]` or `- [x]` line in a markdown file under the vault,
// outside a fenced code block. ws reads the vault each time it lists tasks
// and writes a note only to add a task or tick one.
type task struct {
	Text    string
	Done    bool
	Due     string // YYYY-MM-DD, from 📅 on the line
	State   string // overdue, today, soon, later or none
	Project string
	Section string
	File    string // relative to the vault
	Line    int
}

var (
	taskRe    = regexp.MustCompile(`^\s*- \[([ x])\] +(\S.*)$`)
	headingRe = regexp.MustCompile(`^#{1,6}\s+(.*\S)`)
	fenceRe   = regexp.MustCompile("^\\s*(`{3,}|~{3,})")
	dueRe     = regexp.MustCompile(`\s*📅\s*(\d{4}-\d{2}-\d{2})`)
)

func vaultDir() string {
	return cmp.Or(os.Getenv("VAULT_DIR"), filepath.Join(home, "generic", "vault"))
}

// unfenced calls visit with each line outside a fenced code block.
func unfenced(lines []string, visit func(i int, line string)) {
	fence := ""
	for i, line := range lines {
		if m := fenceRe.FindStringSubmatch(line); m != nil {
			if fence == "" {
				fence = m[1][:1]
			} else if fence == m[1][:1] {
				fence = ""
			}
		} else if fence == "" {
			visit(i, line)
		}
	}
}

// noteProject names the project of a note in the vault: NAME for a note
// under notes/projects/NAME/ or private/notes/projects/NAME/.
func noteProject(file string) string {
	parts := strings.Split(strings.TrimPrefix(file, "private/"), "/")
	if len(parts) > 3 && parts[0] == "notes" && parts[1] == "projects" {
		return parts[2]
	}
	return ""
}

// noteTasks reads the tasks in one note. file is its path in the vault.
func noteTasks(file, content string, today time.Time) []task {
	var ts []task
	project, section := noteProject(file), ""
	unfenced(strings.Split(content, "\n"), func(i int, line string) {
		if h := headingRe.FindStringSubmatch(line); h != nil {
			section = h[1]
		} else if m := taskRe.FindStringSubmatch(line); m != nil {
			t := task{Text: strings.TrimSpace(m[2]), Done: m[1] == "x", State: "none", Project: project, Section: section, File: file, Line: i + 1}
			// An impossible date stays part of the text.
			if d := dueRe.FindStringSubmatch(t.Text); d != nil && validDate(d[1]) {
				t.Due, t.Text = d[1], strings.TrimSpace(strings.Replace(t.Text, d[0], "", 1))
				// ISO dates compare as text.
				switch day := today.Format(time.DateOnly); {
				case t.Due < day:
					t.State = "overdue"
				case t.Due == day:
					t.State = "today"
				case t.Due <= today.AddDate(0, 0, 7).Format(time.DateOnly):
					t.State = "soon"
				default:
					t.State = "later"
				}
			}
			ts = append(ts, t)
		}
	})
	return ts
}

func validDate(s string) bool {
	_, err := time.Parse(time.DateOnly, s)
	return err == nil
}

// vaultTasks reads every task in the vault, skipping hidden folders.
func vaultTasks(vault string, today time.Time) ([]task, error) {
	ts := []task{}
	err := filepath.WalkDir(vault, func(path string, d os.DirEntry, err error) error {
		switch {
		case err != nil:
			return err
		case strings.HasPrefix(d.Name(), ".") && path != vault:
			if d.IsDir() {
				return filepath.SkipDir
			}
		case !d.IsDir() && strings.HasSuffix(path, ".md"):
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(vault, path)
			ts = append(ts, noteTasks(filepath.ToSlash(rel), string(data), today)...)
		}
		return nil
	})
	return ts, err
}

// dueDate reads a due date as a person types it: today, tmr, 3d, a weekday
// such as fri, or an ISO date. A weekday named on that weekday means today,
// and blank means no date.
func dueDate(s string, today time.Time) (string, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	days, isDays := strings.CutSuffix(s, "d")
	n, err := strconv.Atoi(days)
	switch {
	case s == "" || validDate(s):
		return s, nil
	case s == "today":
		n = 0
	case s == "tmr" || s == "tomorrow":
		n = 1
	case isDays && err == nil && n >= 0:
	default:
		day := time.Sunday
		for len(s) < 3 || !strings.HasPrefix(strings.ToLower(day.String()), s) {
			if day++; day > time.Saturday {
				return "", fmt.Errorf("%q is not a date, so use today, tmr, 3d, a weekday such as fri, or YYYY-MM-DD", s)
			}
		}
		n = (int(day-today.Weekday()) + 7) % 7
	}
	return today.AddDate(0, 0, n).Format(time.DateOnly), nil
}

// addTask appends a task to notes/projects/PROJECT/TODO.md, above the first
// ## heading so it sits with the project's tasks rather than a branch's.
func addTask(vault, project, text, due string) error {
	if project == "" {
		return errors.New("this folder has no origin remote to name the task's project")
	}
	file := filepath.Join(vault, "notes", "projects", project, "TODO.md")
	data, err := os.ReadFile(file)
	if errors.Is(err, os.ErrNotExist) {
		data, err = []byte("# "+project+"\n"), os.MkdirAll(filepath.Dir(file), 0o755)
	}
	if err != nil {
		return err
	}
	lines := strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
	at := len(lines)
	unfenced(lines, func(i int, line string) {
		if at == len(lines) && strings.HasPrefix(line, "##") && headingRe.MatchString(line) {
			at = i
		}
	})
	for at > 0 && strings.TrimSpace(lines[at-1]) == "" {
		at--
	}
	entry := []string{"- [ ] " + text}
	if due != "" {
		entry[0] += " 📅 " + due
	}
	if at > 0 && headingRe.MatchString(lines[at-1]) {
		entry = []string{"", entry[0]}
	}
	return os.WriteFile(file, []byte(strings.Join(slices.Insert(lines, at, entry...), "\n")+"\n"), 0o644)
}

// tickTask turns t's box from [ ] to [x] and leaves every other byte of the
// note as it was. It refuses when the line is no longer that open task,
// since the note may have changed after the list loaded.
func tickTask(vault string, t task, today time.Time) error {
	file := filepath.Join(vault, t.File)
	data, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	now := noteTasks(t.File, string(data), today)
	if i := slices.IndexFunc(now, func(c task) bool { return c.Line == t.Line }); i < 0 || now[i].Text != t.Text || now[i].Done {
		return fmt.Errorf("%s:%d changed since the list loaded, so press ^r to refresh", t.File, t.Line)
	}
	lines := strings.SplitAfter(string(data), "\n")
	lines[t.Line-1] = strings.Replace(lines[t.Line-1], "[ ]", "[x]", 1)
	return os.WriteFile(file, []byte(strings.Join(lines, "")), 0o644)
}

func tasksPopup(b mux.Backend, term kitty.Terminal) popup.Popup {
	rex, inRex := b.(mux.Rex)
	vault := vaultDir()
	tags := map[string]lipgloss.Style{"overdue": popup.Red.SetString("overdue"), "today": popup.Yellow.SetString("today"), "soon": popup.Accent.SetString("soon")}
	// A project's tasks are filed under the name of its origin remote.
	project := ""
	if url, err := git(".", "remote", "get-url", "origin"); err == nil {
		url = strings.TrimSuffix(strings.TrimRight(url, "/"), ".git")
		project = url[strings.LastIndexAny(url, "/:")+1:]
	}
	tabs := []popup.Tab{{Name: "Tasks", Empty: "No open tasks."}}
	if project != "" {
		tabs = []popup.Tab{{Name: project, Empty: "No open tasks in " + project + "."}, {Name: "All", Empty: "No open tasks."}}
	}
	return popup.Popup{
		Noun: "tasks",
		Tabs: tabs,
		Load: func(tab int) ([]popup.Row, error) {
			ts, err := vaultTasks(vault, time.Now())
			ts = slices.DeleteFunc(ts, func(t task) bool { return t.Done || project != "" && tab == 0 && t.Project != project })
			// ISO dates sort as text, and undated tasks go last.
			slices.SortStableFunc(ts, func(a, b task) int { return strings.Compare(cmp.Or(a.Due, "~"), cmp.Or(b.Due, "~")) })
			rows := make([]popup.Row, len(ts))
			for i, t := range ts {
				// notes/projects/NAME/TODO.md:4 reads as NAME/TODO.md:4, and as
				// TODO.md:4 on NAME's tab. private/notes/projects/NAME/TODO.md:4
				// reads the same with private/ in front.
				id := t.File + ":" + strconv.Itoa(t.Line)
				note, private := strings.CutPrefix(id, "private/")
				note = strings.TrimPrefix(note, "notes/projects/")
				if project != "" && tab == 0 {
					note = strings.TrimPrefix(note, project+"/")
				}
				if private {
					note = "private/" + note
				}
				rows[i] = popup.Row{ID: id, Title: t.Text, Detail: note, Tag: tags[t.State], Data: t}
				if due, err := time.Parse(time.DateOnly, t.Due); err == nil {
					rows[i].Qualifier = due.Format("Jan 2")
				}
			}
			return rows, err
		},
		// The note around the task, as markdown.
		Fetch: func(r popup.Row) (any, error) {
			t := r.Data.(task)
			file := filepath.Join(vault, t.File)
			data, err := os.ReadFile(file)
			lines := strings.Split(string(data), "\n")
			if err != nil || t.Line > len(lines) {
				return nil, err
			}
			return markdown.Load(strings.Join(lines[max(0, t.Line-6):min(len(lines), t.Line+15)], "\n"), markdownIn(filepath.Dir(file), term)), nil
		},
		Body: func(_ popup.Row, d any, w int) string { return d.(markdown.Doc).Render(w, markdownIn("", term)) },
		Actions: []popup.Action{
			{Key: "enter", Help: "edit", Run: func(r popup.Row) tea.Cmd {
				t := r.Data.(task)
				line := "+" + strconv.Itoa(t.Line)
				if !inRex {
					return tea.ExecProcess(exec.Command("nvim", line, filepath.Join(vault, t.File)), func(err error) tea.Msg {
						if err != nil {
							return popup.Notice(err.Error())
						}
						return popup.Reload("")
					})
				}
				return popup.Do(func() error { return rex.Tab(os.Getenv("REX_SESSION"), vault, "nvim", line, t.File) }, popup.Quit)
			}},
			{Key: "ctrl+t", Help: "add", Always: true, Run: func(popup.Row) tea.Cmd {
				return popup.Ask("task:", func(text string) tea.Cmd {
					if text == "" {
						return nil
					}
					return popup.Ask("due, such as fri or 3d (blank for none):", func(due string) tea.Cmd {
						return popup.Do(func() error {
							date, err := dueDate(due, time.Now())
							if err != nil {
								return err
							}
							return addTask(vault, project, text, date)
						}, popup.Reload("added: "+text))
					})
				})
			}},
			{Key: "ctrl+x", Help: "done", Run: func(r popup.Row) tea.Cmd {
				t := r.Data.(task)
				return popup.Do(func() error { return tickTask(vault, t, time.Now()) }, popup.Reload("done: "+t.Text))
			}},
		},
	}
}
