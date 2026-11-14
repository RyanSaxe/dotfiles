package markdown_test

import (
	"errors"
	"image"
	"slices"
	"strings"
	"testing"

	"workspace/markdown"
)

// Code blocks take Catppuccin's colors in true color, so Go's `func` is
// Mocha's red.
func TestCodeBlocksUseCatppuccin(t *testing.T) {
	o := markdown.Options{Dark: true}
	out := markdown.Load("```go\nfunc main() {}\n```\n", o).Render(40, o)
	if !strings.Contains(out, "38;2;243;139;168mfunc") {
		t.Errorf("func isn't in Catppuccin Mocha's red in %q", out)
	}
}

// A style passed in colors both the text and the code: here a heading in
// one red and Go's `func` in one purple.
func TestStyleColorsTextAndCode(t *testing.T) {
	style := `{"h1": {"color": "#ff0000"}, "code_block": {"chroma": {"keyword": {"color": "#8800ff"}}}}`
	o := markdown.Options{Dark: true, Style: []byte(style)}
	out := markdown.Load("# Title\n\n```go\nfunc main() {}\n```\n", o).Render(40, o)
	if !strings.Contains(out, "38;2;255;0;0m") || !strings.Contains(out, "38;2;136;0;255mfunc") {
		t.Errorf("the heading or `func` doesn't take the style's color in %q", out)
	}
}

// Only a picture or a mermaid fence in prose becomes a picture. Inside a code
// block, both are code, including a line that reads like a mermaid fence.
func TestPicturesComeFromProseOnly(t *testing.T) {
	md := "![shot](a.png)\n\n```go\n![not a picture](b.png)\n```mermaid\nnot a diagram\n```\n\n```mermaid\ngraph LR; a-->b\n```\n"
	var fetched, drawn []string
	none := errors.New("not loaded in a test")
	markdown.Load(md, markdown.Options{
		Fetch:   func(src string) (image.Image, error) { fetched = append(fetched, src); return nil, none },
		Mermaid: func(src string, _ bool) (image.Image, error) { drawn = append(drawn, src); return nil, none },
	})
	if !slices.Equal(fetched, []string{"a.png"}) || !slices.Equal(drawn, []string{"graph LR; a-->b"}) {
		t.Errorf("fetched %v and drew %v, want [a.png] and the one diagram", fetched, drawn)
	}
}
