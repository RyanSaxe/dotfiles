package main

import (
	"bytes"
	"cmp"

	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"workspace/kitty"
	"workspace/popup"
)

// A mascot is named provider:id. pokemon and shiny-pokemon come from
// PokeAPI and are cached, and local is a PNG file on this computer.
type mascot struct {
	sprite  string // the picture popups draw
	palette string // the picture its colors come from, which may be richer than the sprite
}

var mascotCache = filepath.Join(cmp.Or(os.Getenv("XDG_CACHE_HOME"), filepath.Join(home, ".cache")), "dotfiles", "mascots")

// localMascots is where the theme popup finds local PNG mascots by name.
var localMascots = filepath.Join(cmp.Or(os.Getenv("XDG_DATA_HOME"), filepath.Join(home, ".local", "share")), "dotfiles", "mascots")

// mascotName makes a bare Pokémon name or a PNG path into a provider:id name.
func mascotName(name string) (string, error) {
	switch {
	case strings.Contains(name, ":"):
		return name, nil
	case strings.HasSuffix(strings.ToLower(name), ".png"):
		abs, err := filepath.Abs(name)
		return "local:" + abs, err
	}
	return "pokemon:" + strings.ToLower(name), nil
}

func fetchMascot(name string) (mascot, error) {
	provider, id, _ := strings.Cut(name, ":")
	switch provider {
	case "local":
		path := id
		if !filepath.IsAbs(path) {
			path = filepath.Join(localMascots, id)
		}
		if _, err := os.Stat(path); err != nil {
			return mascot{}, fmt.Errorf("no local mascot at %s", path)
		}
		return mascot{path, path}, nil
	case "pokemon", "shiny-pokemon":
		return fetchPokemon(id, provider == "shiny-pokemon")
	}
	return mascot{}, fmt.Errorf("%s is not pokemon:NAME, shiny-pokemon:NAME or local:FILE.png", name)
}

// fetchPokemon caches a Pokémon's game sprite, which popups draw, and its
// official artwork, which keeps details the small sprite drops, such as
// gengar's red eyes, for its colors.
func fetchPokemon(name string, shiny bool) (mascot, error) {
	dir := filepath.Join(mascotCache, "pokemon")
	base, variant := name, "front_default"
	if shiny {
		base, variant = name+"-shiny", "front_shiny"
	}
	m := mascot{filepath.Join(dir, base+"-sprite.png"), filepath.Join(dir, base+".png")}
	_, errS := os.Stat(m.sprite)
	_, errP := os.Stat(m.palette)
	if errS == nil && errP == nil {
		return m, nil
	}
	data, err := get("https://pokeapi.co/api/v2/pokemon/" + name)
	if err != nil {
		return m, err
	}
	var info struct {
		Sprites map[string]any
	}
	if err := json.Unmarshal(data, &info); err != nil {
		return m, err
	}
	sprite, _ := info.Sprites[variant].(string)
	artwork := ""
	if other, ok := info.Sprites["other"].(map[string]any); ok {
		if art, ok := other["official-artwork"].(map[string]any); ok {
			artwork, _ = art[variant].(string)
		}
	}
	if sprite == "" || artwork == "" {
		return m, fmt.Errorf("PokeAPI has no %s pictures of %s", strings.TrimPrefix(variant, "front_"), name)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return m, err
	}
	for path, url := range map[string]string{m.sprite: sprite, m.palette: artwork} {
		data, err := get(url)
		if err == nil {
			err = os.WriteFile(path, data, 0o644)
		}
		if err != nil {
			return m, err
		}
	}
	return m, nil
}

func get(url string) ([]byte, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "ws") // PokeAPI refuses Go's default
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

// pokemonNames lists every Pokémon, fetched once and cached.
func pokemonNames() ([]string, error) {
	file := filepath.Join(mascotCache, "pokemon", "names.txt")
	data, err := os.ReadFile(file)
	if errors.Is(err, os.ErrNotExist) {
		var list []byte
		if list, err = get("https://pokeapi.co/api/v2/pokemon/?limit=100000"); err == nil {
			var res struct{ Results []struct{ Name string } }
			if err = json.Unmarshal(list, &res); err == nil {
				var b strings.Builder
				for _, r := range res.Results {
					b.WriteString(r.Name + "\n")
				}
				data = []byte(b.String())
				os.MkdirAll(filepath.Dir(file), 0o755)
				err = os.WriteFile(file, data, 0o644)
			}
		}
	}
	return strings.Fields(string(data)), err
}

func loadPNG(path string) (image.Image, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return png.Decode(bytes.NewReader(data))
}

// ----- colors ------------------------------------------------------------
//
// mascotColors finds the mascot's two hues as the theme command did: the
// dominant vivid hue, or the dominant pale one when nothing is vivid, and
// the most distinct other hue the mascot actually has. Then each snaps to
// the Catppuccin accent nearest in OKLCH hue, the second to a different
// accent than the first.

type hsv struct{ h, s, v float64 }

const hueBuckets = 24 // 15 degrees each

// mochaAccents are Catppuccin's accents that carry a hue. rosewater and
// flamingo are near white, so they never win.
var mochaAccents = []struct{ name, hex string }{
	{"pink", "#f5c2e7"}, {"mauve", "#cba6f7"}, {"red", "#f38ba8"}, {"maroon", "#eba0ac"},
	{"peach", "#fab387"}, {"yellow", "#f9e2af"}, {"green", "#a6e3a1"}, {"teal", "#94e2d5"},
	{"sky", "#89dceb"}, {"sapphire", "#74c7ec"}, {"blue", "#89b4fa"}, {"lavender", "#b4befe"},
}

func mascotColors(img image.Image) (accent, notify string, err error) {
	vivid, pale := gatherPixels(img)
	if len(vivid) == 0 && len(pale) == 0 {
		return "", "", errors.New("the picture is grey, so it has no hue to take")
	}
	a, n := pickPair(vivid, pale)
	if isRed(a) && !isRed(n) { // an overly red accent reads as an error
		a, n = n, a
	}
	accent = nearestAccent(darkStyled(a, false), "")
	return accent, nearestAccent(darkStyled(n, true), accent), nil
}

// gatherPixels splits the picture's opaque, tinted pixels into vivid and
// pale, after averaging it down to at most 96 pixels on a side. Averaging,
// not sampling, keeps small features such as eyes.
func gatherPixels(img image.Image) (vivid, pale []hsv) {
	b := img.Bounds()
	side := max(b.Dx(), b.Dy())
	cell := max(1, float64(side)/96)
	for ty := 0; float64(ty)*cell < float64(b.Dy()); ty++ {
		for tx := 0; float64(tx)*cell < float64(b.Dx()); tx++ {
			var r, g, bl, a float64
			n := 0
			for y := b.Min.Y + int(float64(ty)*cell); y < min(b.Max.Y, b.Min.Y+int(float64(ty+1)*cell)); y++ {
				for x := b.Min.X + int(float64(tx)*cell); x < min(b.Max.X, b.Min.X+int(float64(tx+1)*cell)); x++ {
					c := color.NRGBAModel.Convert(img.At(x, y)).(color.NRGBA)
					w := float64(c.A) // color weighs by its opacity
					r, g, bl, a, n = r+float64(c.R)*w, g+float64(c.G)*w, bl+float64(c.B)*w, a+w, n+1
				}
			}
			if n == 0 || a/float64(n) < 128 {
				continue
			}
			p := toHSV(r/a/255, g/a/255, bl/a/255)
			switch {
			case p.v < 0.2 || p.v > 0.98: // black and white carry no hue
			case p.s >= 0.25:
				vivid = append(vivid, p)
			case p.s >= 0.10:
				pale = append(pale, p)
			}
		}
	}
	return vivid, pale
}

func bucket(h float64) int { return int(h*hueBuckets) % hueBuckets }

func bucketGap(a, b int) int {
	d := abs(a - b)
	return min(d, hueBuckets-d)
}

func abs(n int) int { return max(n, -n) }

func weights(px []hsv) []float64 {
	w := make([]float64, hueBuckets)
	for _, p := range px {
		w[bucket(p.h)] += p.s * p.v
	}
	return w
}

// representative is a hue cluster's vivid heart: the mean of its most
// saturated quarter.
func representative(px []hsv, b int) hsv {
	var members []hsv
	for _, p := range px {
		if bucketGap(bucket(p.h), b) <= 1 {
			members = append(members, p)
		}
	}
	slices.SortFunc(members, func(x, y hsv) int { return cmp.Compare(y.s*y.v, x.s*x.v) })
	top := members[:max(1, len(members)/4)]
	center := (float64(b) + 0.5) / hueBuckets
	var h, s, v float64
	for _, p := range top {
		h += math.Mod(p.h-center+1.5, 1) - 0.5 // recentered so the mean is safe across 0 and 1
		s += p.s
		v += p.v
	}
	n := float64(len(top))
	return hsv{math.Mod(h/n+center+1, 1), s / n, v / n}
}

func pickPair(vivid, pale []hsv) (hsv, hsv) {
	lead := vivid
	if len(lead) == 0 { // a mascot painted only in dusty colors, such as mewtwo
		lead = pale
	}
	lw := weights(lead)
	primary := 0
	for i := range lw {
		if lw[i] > lw[primary] {
			primary = i
		}
	}
	threshold := lw[primary] * 0.02 // a cluster this much weaker is noise
	accent := representative(lead, primary)
	tiers := []struct {
		px  []hsv
		w   []float64
		gap int
	}{{lead, lw, 3}, {lead, lw, 2}, {pale, weights(pale), 2}}
	for _, t := range tiers {
		best := -1
		for i := range t.w {
			if bucketGap(i, primary) >= t.gap && t.w[i] > threshold && (best < 0 || t.w[i] > t.w[best]) {
				best = i
			}
		}
		if best >= 0 {
			return accent, representative(t.px, best)
		}
	}
	return accent, accent
}

func isRed(c hsv) bool {
	return min(c.h, 1-c.h) <= 12.0/360 && c.s >= 0.45
}

// darkStyled is the pastel the theme command gave a hue on a dark
// background, which is what the snapping compares.
func darkStyled(c hsv, bright bool) [3]float64 {
	v := 0.85
	if bright {
		v = 0.92
	}
	r, g, b := fromHSV(c.h, min(max(c.s, 0.55), 0.85), v)
	return [3]float64{r, g, b}
}

// nearestAccent is the accent closest in OKLCH hue, other than not.
func nearestAccent(rgb [3]float64, not string) string {
	h := okHue(rgb)
	best, bestGap := "", 361.0
	for _, a := range mochaAccents {
		if a.name == not {
			continue
		}
		var c [3]float64
		for i := range c {
			var n int
			fmt.Sscanf(a.hex[1+2*i:3+2*i], "%x", &n)
			c[i] = float64(n) / 255
		}
		d := math.Abs(okHue(c) - h)
		if d = min(d, 360-d); d < bestGap {
			best, bestGap = a.name, d
		}
	}
	return best
}

// okHue is a color's hue angle in OKLab, in degrees.
func okHue(rgb [3]float64) float64 {
	var lin [3]float64
	for i, c := range rgb {
		if c <= 0.04045 {
			lin[i] = c / 12.92
		} else {
			lin[i] = math.Pow((c+0.055)/1.055, 2.4)
		}
	}
	r, g, b := lin[0], lin[1], lin[2]
	l := math.Cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
	m := math.Cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
	s := math.Cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
	A := 1.9779984951*l - 2.4285922050*m + 0.4505937099*s
	B := 0.0259040371*l + 0.7827717662*m - 0.8086757660*s
	return math.Mod(math.Atan2(B, A)*180/math.Pi+360, 360)
}

func toHSV(r, g, b float64) hsv {
	hi, lo := max(r, g, b), min(r, g, b)
	d := hi - lo
	if hi == 0 {
		return hsv{0, 0, 0}
	}
	var h float64
	switch {
	case d == 0:
	case hi == r:
		h = math.Mod((g-b)/d, 6)
	case hi == g:
		h = (b-r)/d + 2
	default:
		h = (r-g)/d + 4
	}
	return hsv{math.Mod(h/6+1, 1), d / hi, hi}
}

func fromHSV(h, s, v float64) (r, g, b float64) {
	i := math.Floor(h * 6)
	f := h*6 - i
	p, q, t := v*(1-s), v*(1-s*f), v*(1-s*(1-f))
	switch int(i) % 6 {
	case 0:
		return v, t, p
	case 1:
		return q, v, p
	case 2:
		return p, v, t
	case 3:
		return p, q, v
	case 4:
		return t, p, v
	}
	return v, p, q
}

// ----- drawing -------------------------------------------------------------

// drawSprite draws a picture in text, two pixels to a cell with half
// blocks in true color, cropped to what is opaque and shrunk to fit w
// cells by h cells. It shows wherever the terminal does, a phone included.
func drawSprite(img image.Image, w, h int) string {
	box := opaqueBounds(img)
	if box.Empty() {
		return ""
	}
	step := max(1, (box.Dx()+w-1)/w, (box.Dy()+2*h-1)/(2*h))
	at := func(x, y int) (color.NRGBA, bool) {
		if x >= box.Max.X || y >= box.Max.Y {
			return color.NRGBA{}, false
		}
		c := color.NRGBAModel.Convert(img.At(x, y)).(color.NRGBA)
		return c, c.A >= 128
	}
	var b strings.Builder
	for y := box.Min.Y; y < box.Max.Y; y += 2 * step {
		for x := box.Min.X; x < box.Max.X; x += step {
			top, hasTop := at(x, y)
			bot, hasBot := at(x, y+step)
			switch {
			case hasTop && hasBot:
				fmt.Fprintf(&b, "\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm▀\x1b[m", top.R, top.G, top.B, bot.R, bot.G, bot.B)
			case hasTop:
				fmt.Fprintf(&b, "\x1b[38;2;%d;%d;%dm▀\x1b[m", top.R, top.G, top.B)
			case hasBot:
				fmt.Fprintf(&b, "\x1b[38;2;%d;%d;%dm▄\x1b[m", bot.R, bot.G, bot.B)
			default:
				b.WriteByte(' ')
			}
		}
		b.WriteByte('\n')
	}
	return strings.TrimSuffix(b.String(), "\n")
}

func opaqueBounds(img image.Image) image.Rectangle {
	b, box := img.Bounds(), image.Rectangle{}
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if _, _, _, a := img.At(x, y).RGBA(); a >= 0x8000 {
				box = box.Union(image.Rect(x, y, x+1, y+1))
			}
		}
	}
	return box
}

// ----- the mascot in every popup's header ---------------------------------

// mascotImageID names the image to the terminal. Each popup sends the same
// mascot, so one id is enough, and a new popup replaces the last one's.
const mascotImageID = kitty.ID(0x575301)

// mascotArt draws the theme's mascot rows cells tall, or nothing when the
// terminal can't draw it, there is no theme, or the sprite isn't cached. Half
// blocks this small are a smudge, so there's no other way to draw it.
func mascotArt(rows int, term kitty.Terminal) popup.Art {
	if !term.Draws {
		return popup.Art{}
	}
	c, err := readTheme()
	var m mascot
	if err == nil {
		m, err = fetchMascot(c.Mascot)
	}
	var img image.Image
	if err == nil {
		img, err = loadPNG(m.sprite)
	}
	if err != nil {
		return popup.Art{}
	}
	box := opaqueBounds(img)
	if box.Empty() {
		return popup.Art{}
	}
	// A cell is about twice as tall as it is wide.
	cols := max(1, int(math.Round(float64(2*rows*box.Dx())/float64(box.Dy()))))
	crop := image.NewNRGBA(image.Rect(0, 0, box.Dx(), box.Dy()))
	draw.Draw(crop, crop.Bounds(), img, box.Min, draw.Src)
	var data bytes.Buffer
	png.Encode(&data, crop)
	return popup.Art{Cells: kitty.Placeholders(mascotImageID, cols, rows), Setup: term.Image(data.Bytes(), mascotImageID, cols, rows), Cols: cols, Rows: rows}
}
