package main

import (
	"image"
	"image/color"
	"testing"
)

// paint is a transparent picture with rectangles of color.
// layer is one rectangle of paint. paint draws layers in order, so a later
// one covers an earlier one where they overlap.
type layer struct {
	r image.Rectangle
	c color.NRGBA
}

func paint(layers ...layer) image.Image {
	img := image.NewNRGBA(image.Rect(0, 0, 200, 200))
	for _, l := range layers {
		for y := l.r.Min.Y; y < l.r.Max.Y; y++ {
			for x := l.r.Min.X; x < l.r.Max.X; x++ {
				img.SetNRGBA(x, y, l.c)
			}
		}
	}
	return img
}

var (
	crimson = color.NRGBA{220, 30, 40, 255}
	gold    = color.NRGBA{220, 180, 60, 255}
	blush   = color.NRGBA{245, 195, 205, 255}
	teal    = color.NRGBA{40, 170, 190, 255}
	grey    = color.NRGBA{128, 128, 128, 255}
)

func TestMascotAccent(t *testing.T) {
	for _, tc := range []struct {
		name   string
		img    image.Image
		accent string
	}{
		// Jigglypuff's case: a pale pink body outweighs small vivid eyes.
		{"a pale body outweighs vivid eyes", paint(
			layer{image.Rect(0, 0, 200, 200), blush}, layer{image.Rect(50, 50, 70, 70), teal}, layer{image.Rect(130, 50, 150, 70), teal},
		), "maroon"},
		// A mostly red mascot leads with its other hue, since a red accent
		// reads as an error everywhere it shows.
		{"red never leads", paint(
			layer{image.Rect(0, 0, 200, 150), crimson}, layer{image.Rect(0, 150, 200, 200), gold},
		), "yellow"},
	} {
		accent, err := mascotAccent(tc.img)
		if err != nil || accent != tc.accent {
			t.Errorf("%s: got %s (%v), want %s", tc.name, accent, err, tc.accent)
		}
	}
	if _, err := mascotAccent(paint(layer{image.Rect(0, 0, 200, 200), grey})); err == nil {
		t.Error("a grey picture has no hue, but mascotAccent found one")
	}
}
