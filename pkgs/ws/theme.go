package main

import (
	"bytes"
	"cmp"
	"encoding/json"
	"errors"
	"image"
	"image/draw"
	"image/png"
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"workspace/kitty"
	"workspace/popup"
)

// themeChoice is a computer's mascot and the two Catppuccin accents its
// colors snapped to, which color the popups. Only ws reads and writes it, as
// mascot.json in stateDir.
type themeChoice struct {
	Mascot string `json:"mascot"`
	Accent string `json:"accent"`
	Notify string `json:"notify"`
}

// readTheme is the saved choice, or the default mascot on a computer that
// has saved none.
func readTheme() (themeChoice, error) {
	c := themeChoice{Mascot: "pokemon:raikou", Accent: "yellow", Notify: "sky"}
	err := readJSON("mascot.json", &c)
	if errors.Is(err, os.ErrNotExist) {
		err = nil
	}
	return c, err
}

// themeMode is light or dark, as the theme command last set it.
func themeMode() string {
	data, _ := os.ReadFile(filepath.Join(home, ".config", "theme", "mode"))
	return cmp.Or(strings.TrimSpace(string(data)), "dark")
}

// accentColor is the mascot's accent in the current mode's Catppuccin
// palette, which the ws module names in WS_PALETTE, or "" without one.
func accentColor() string {
	c, err := readTheme()
	if err != nil || c.Accent == "" {
		return ""
	}
	data, err := os.ReadFile(os.Getenv("WS_PALETTE"))
	type flavor struct {
		Colors map[string]struct{ Hex string }
	}
	var palette struct{ Latte, Mocha flavor }
	if err != nil || json.Unmarshal(data, &palette) != nil {
		return ""
	}
	if themeMode() == "light" {
		return palette.Latte.Colors[c.Accent].Hex
	}
	return palette.Mocha.Colors[c.Accent].Hex
}

// setMascot takes the mascot's two colors from its picture and applies it.
func setMascot(name string) error {
	name, err := mascotName(name)
	if err != nil {
		return err
	}
	m, err := fetchMascot(name)
	if err != nil {
		return err
	}
	img, err := loadPNG(m.palette)
	if err != nil {
		return err
	}
	c, err := readTheme()
	if err != nil {
		return err
	}
	if c.Accent, c.Notify, err = mascotColors(img); err != nil {
		return err
	}
	c.Mascot = name
	return writeJSON("mascot.json", c)
}

// spriteImageID names the theme popup's preview to the terminal, apart from
// the header's mascot.
const spriteImageID = kitty.ID(0x575302)

// spritePreview draws a mascot w columns wide: as a Kitty image cropped to
// its opaque pixels where the terminal draws one, and in half blocks
// elsewhere. A cell is about twice as tall as it is wide.
func spritePreview(img image.Image, w int, term kitty.Terminal) string {
	box := opaqueBounds(img)
	if !term.Draws || box.Empty() {
		return drawSprite(img, w, w/2)
	}
	crop := image.NewNRGBA(image.Rect(0, 0, box.Dx(), box.Dy()))
	draw.Draw(crop, crop.Bounds(), img, box.Min, draw.Src)
	var data bytes.Buffer
	png.Encode(&data, crop)
	rows := min(20, w/2)
	cols := min(w, max(1, 2*rows*box.Dx()/box.Dy()))
	// Centered in the pane, below a blank line.
	pad := strings.Repeat(" ", (w-cols)/2)
	cells := strings.Split(kitty.Placeholders(spriteImageID, cols, rows), "\n")
	for i := range cells {
		cells[i] = pad + cells[i]
	}
	return "\n" + term.Image(data.Bytes(), spriteImageID, cols, rows) + strings.Join(cells, "\n")
}

// mode is a Mode tab row's light or dark.
type mode string

func themePopup(term kitty.Terminal) popup.Popup {
	// A tab per kind of mascot, and Yours only on a computer with PNGs.
	locals, _ := filepath.Glob(filepath.Join(localMascots, "*.png"))
	kinds := []string{"", "pokemon", "shiny-pokemon"}
	tabs := []popup.Tab{{Name: "Mode", Empty: "No modes."}, {Name: "Pokémon", Empty: "No Pokémon."}, {Name: "Shiny", Empty: "No shiny Pokémon."}}
	if len(locals) > 0 {
		kinds, tabs = append(kinds, "local"), append(tabs, popup.Tab{Name: "Yours", Empty: "No PNGs in " + tilde(localMascots) + "."})
	}
	return popup.Popup{
		Noun: "modes and mascots", OneLine: true,
		Tabs: tabs,
		Load: func(t int) ([]popup.Row, error) {
			c, err := readTheme()
			if err != nil {
				return nil, err
			}
			current := func(r popup.Row, on bool) popup.Row {
				if on {
					r.Tag = popup.Accent.SetString("current")
				}
				return r
			}
			if t == 0 {
				return []popup.Row{
					current(popup.Row{ID: "mode:dark", Title: "Dark", Data: mode("dark")}, themeMode() == "dark"),
					current(popup.Row{ID: "mode:light", Title: "Light", Data: mode("light")}, themeMode() == "light"),
				}, nil
			}
			var ids []string
			if kinds[t] == "local" {
				for _, f := range locals {
					ids = append(ids, filepath.Base(f))
				}
			} else {
				ids, err = pokemonNames()
			}
			// The current mascot leads its tab.
			var rows []popup.Row
			for _, id := range ids {
				name := kinds[t] + ":" + id
				r := current(popup.Row{ID: name, Title: id, Data: name}, name == c.Mascot)
				if name == c.Mascot {
					rows = append([]popup.Row{r}, rows...)
				} else {
					rows = append(rows, r)
				}
			}
			return rows, err
		},
		Fetch: func(r popup.Row) (any, error) {
			name, ok := r.Data.(string)
			if !ok {
				return "Enter switches macOS and every app to " + r.Title + ".", nil
			}
			m, err := fetchMascot(name)
			if err != nil {
				return nil, err
			}
			return loadPNG(m.sprite)
		},
		Body: func(_ popup.Row, d any, w int) string { return spritePreview(d.(image.Image), w, term) },
		Actions: []popup.Action{{Key: "enter", Help: "apply", Run: func(r popup.Row) tea.Cmd {
			return tea.Batch(popup.Say("switching to "+r.Title+"…"), popup.Do(func() error {
				if m, ok := r.Data.(mode); ok {
					// The theme command flips macOS and every app.
					_, err := runIn("", "theme", string(m))
					return err
				}
				return setMascot(r.Data.(string))
			}, popup.Reload("switched to "+r.Title)))
		}}},
	}
}
