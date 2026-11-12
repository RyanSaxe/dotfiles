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
	purple  = color.NRGBA{100, 70, 200, 255}
	crimson = color.NRGBA{220, 30, 40, 255}
	gold    = color.NRGBA{220, 180, 60, 255}
	grey    = color.NRGBA{128, 128, 128, 255}
)

func TestMascotColors(t *testing.T) {
	for _, tc := range []struct {
		name           string
		img            image.Image
		accent, notify string
	}{
		// Gengar's case: red eyes, 2% of a purple body, still give the
		// second color.
		{"small eyes keep their hue", paint(
			layer{image.Rect(0, 0, 200, 200), purple}, layer{image.Rect(50, 50, 70, 70), crimson}, layer{image.Rect(130, 50, 150, 70), crimson},
		), "lavender", "maroon"},
		// A mostly red mascot leads with its other hue, since a red accent
		// reads as an error everywhere it shows.
		{"red never leads", paint(
			layer{image.Rect(0, 0, 200, 150), crimson}, layer{image.Rect(0, 150, 200, 200), gold},
		), "yellow", "maroon"},
		// One hue still gives two different accents.
		{"one hue gives two accents", paint(layer{image.Rect(0, 0, 200, 200), gold}), "yellow", "peach"},
	} {
		accent, notify, err := mascotColors(tc.img)
		if err != nil || accent != tc.accent || notify != tc.notify {
			t.Errorf("%s: got %s and %s (%v), want %s and %s", tc.name, accent, notify, err, tc.accent, tc.notify)
		}
	}
	if _, _, err := mascotColors(paint(layer{image.Rect(0, 0, 200, 200), grey})); err == nil {
		t.Error("a grey picture has no hue, but mascotColors found one")
	}
}
