package markdown_test

import (
	"errors"
	"image"
	"slices"
	"testing"

	"workspace/markdown"
)

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
