# Diagrams

## Reference a light and a dark file

Write each diagram as two SVG files, `NAME-light.svg` and `NAME-dark.svg`. A `<picture>` element shows the dark file
to readers whose system uses a dark theme and the light file to everyone else:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/NAME-dark.svg">
  <img alt="A full description of what the diagram shows." src="assets/NAME-light.svg">
</picture>
```

Some readers can't see the diagram. Write the alt text so it tells them everything the diagram shows, and put the
same text in the SVG's `aria-label`.

## Start from this template

Generate both files from one script. The dark file is the light file with one extra line of colour rules, so a change
to the drawing reaches both.

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 596 406" role="img" aria-label="...">
<style>
text{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;fill:#1f2328;text-anchor:middle;font-size:17px}
.t{font-weight:600}.s{font-size:14px;fill:#59636e}
.line{fill:none;stroke:#1f2328;stroke-width:1.5}.head{fill:#1f2328}
.box{fill:#ffffff;stroke:#b8bec6}.round{fill:#eef2fd;stroke:#3a5bd9}
</style>
<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" class="head"/></marker></defs>
<rect class="box" x="18" y="18" width="250" height="100" rx="10"/>
<text x="143" y="54" class="t">Title</text>
<text x="143" y="79" class="s">One short line about it</text>
<path class="line" d="M268 68 H324" marker-end="url(#a)"/>
</svg>
```

For the dark file, add this line at the end of the style block:

```css
text{fill:#e6edf3}.s{fill:#9198a1}.line{stroke:#e6edf3}.head{fill:#e6edf3}.box{fill:#0d1117;stroke:#3d444d}.round{fill:#152042;stroke:#6e8cf0}
```

## Lay it out for a phone

A phone shows the diagram about 350 pixels wide, so its size and the amount of text in it decide whether anyone can
read it.

- Draw only the parts the reader needs to follow the explanation. Four to six boxes is usually enough.
- Make the `viewBox` about 600 units wide and use text sizes of 14 or more. A wider drawing shrinks its text below a
  readable size.
- Arrange four steps in a loop as a two-by-two grid. One row of four boxes is too wide.
- Give each box a title and at most two short lines.
- Use the accent colour (`.round`) for the one box the diagram is about.
- Place each label beside the end of its arrow, clear of other arrows and labels. Draw an arrow that returns to an
  earlier box with square corners.

## Look at both files

Open both files in a browser at full width and at phone width, on a light and a dark background. Then open the page
that uses them on its host.
