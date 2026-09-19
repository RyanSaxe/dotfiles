import assert from "node:assert/strict";
import { test } from "node:test";
import { assemble } from "./build.mjs";

const data = {
  artifactId: "t",
  revision: "1",
  kind: "exploration",
  title: "T",
  pages: [{ id: "p", title: "P", html: "<p>x</p>" }],
};

test("plan CSS is scoped to the page content", async () => {
  const html = await assemble(data, { css: "body{background:red}" });
  assert.match(
    html,
    /@scope \(#page-content\) \{\nbody\{background:red\}\n\}\n<\/style>/,
  );
});

test("a closing style tag in plan CSS is refused", async () => {
  await assert.rejects(
    assemble(data, { css: "</style><script>1</script>" }),
    /closing style/,
  );
});
