const $ = (id) => document.getElementById(id);
const session = JSON.parse($("session-config").textContent);

function paint(state) {
  $("repo-name").textContent = state.repo.name;
  $("repo-ref").textContent =
    state.repo.ref +
    (state.repo.refType === "branch" ? " · committed content only" : "");
}

async function poll() {
  try {
    const response = await fetch("/api/state");
    if (response.ok) paint(await response.json());
  } catch {
    /* Keep the page readable while the helper is unreachable. */
  }
}

paint({ repo: session.repo });
poll();
setInterval(poll, 1000);
