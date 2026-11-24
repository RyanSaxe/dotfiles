package main

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sync"
	"time"
	"workspace/kitty"
	"workspace/markdown"
)

// markdownIn is how this program renders markdown: in the theme's glamour
// style for the current mode, with pictures from dir, GitHub and mmdc.
func markdownIn(dir string, term kitty.Terminal) markdown.Options {
	style, _ := os.ReadFile(filepath.Join(home, ".config", "theme", "glamour.json"))
	return markdown.Options{
		Dark:     darkMode(),
		Style:    style,
		Terminal: term,
		Fetch:    func(src string) (image.Image, error) { return loadImage(src, dir) },
		Mermaid:  mermaidPNG,
	}
}

var (
	httpClient   = &http.Client{Timeout: 10 * time.Second}
	mermaidCache = filepath.Join(filepath.Dir(mascotCache), "mermaid")
	// A file in a private repository opens with gh's token only from
	// GitHub's raw host, so a link to the file's page goes there instead.
	fileLink = regexp.MustCompile(`^https://github\.com/([^/]+/[^/]+)/(?:blob|raw)/([^?]+)(?:\?raw=true)?$`)
	ghToken  = sync.OnceValue(func() string { t, _ := runIn("", "gh", "auth", "token"); return t })
)

func loadImage(src, dir string) (image.Image, error) {
	r, err := openImage(src, dir)
	if err != nil {
		return nil, err
	}
	defer func() { _ = r.Close() }()
	img, _, err := image.Decode(r)
	return img, err
}

func openImage(src, dir string) (io.ReadCloser, error) {
	if m := fileLink.FindStringSubmatch(src); m != nil {
		src = "https://raw.githubusercontent.com/" + m[1] + "/" + m[2]
	}
	if u, err := url.Parse(src); err == nil && (u.Scheme == "http" || u.Scheme == "https") {
		return fetchImageURL(u, src)
	}
	return os.Open(filepath.Join(dir, src)) //nolint:gosec // opens local markdown image relative to document dir
}

func fetchImageURL(u *url.URL, src string) (io.ReadCloser, error) {
	req, err := http.NewRequest("GET", src, nil)
	if err != nil {
		return nil, err
	}
	if u.Host == "raw.githubusercontent.com" {
		if t := ghToken(); t != "" {
			req.Header.Set("Authorization", "token "+t)
		}
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		_ = resp.Body.Close()
		return nil, fmt.Errorf("%s: %s", src, resp.Status)
	}
	return resp.Body, nil
}

// mermaidThemes color diagrams like the terminal around them, in
// Catppuccin Mocha and Latte with the theme's chrome color as mantle.
var mermaidThemes = map[bool]string{
	true:  `{"theme":"base","themeVariables":{"background":"#1e1e2e","primaryColor":"#313244","primaryTextColor":"#cdd6f4","primaryBorderColor":"#89b4fa","lineColor":"#9399b2","secondaryColor":"#45475a","tertiaryColor":"#1a1a27","fontFamily":"Menlo"}}`,
	false: `{"theme":"base","themeVariables":{"background":"#eff1f5","primaryColor":"#ccd0da","primaryTextColor":"#4c4f69","primaryBorderColor":"#1e66f5","lineColor":"#7c7f93","secondaryColor":"#bcc0cc","tertiaryColor":"#eaebee","fontFamily":"Menlo"}}`,
}

// mermaidPNG renders a diagram with mmdc once and keeps the PNG by the hash
// of its source and colors.
func mermaidPNG(src string, dark bool) (image.Image, error) {
	config := mermaidThemes[dark]
	out := filepath.Join(mermaidCache, fmt.Sprintf("%x.png", sha256.Sum256([]byte(config+src))))
	if _, err := os.Stat(out); err != nil {
		if err := renderMermaid(src, config, out); err != nil {
			return nil, err
		}
	}
	return loadImage(out, "")
}

func renderMermaid(src, config, out string) error {
	if err := os.MkdirAll(mermaidCache, 0o750); err != nil {
		return err
	}
	in, cfg := out+".mmd", out+".json"
	defer func() { _ = os.Remove(in) }()
	defer func() { _ = os.Remove(cfg) }()
	if err := os.WriteFile(in, []byte(src), 0o600); err != nil {
		return err
	}
	if err := os.WriteFile(cfg, []byte(config), 0o600); err != nil {
		return err
	}
	if b, err := exec.Command("mmdc", "-q", "-i", in, "-o", out, "-c", cfg, "-b", "transparent", "-s", "2").CombinedOutput(); err != nil { //nolint:gosec // invokes local mmdc renderer with cache paths
		return fmt.Errorf("mmdc: %s", bytes.TrimSpace(b))
	}
	return nil
}

func darkMode() bool { return themeMode() != "light" }
