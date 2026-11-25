---
name: wiki
description: Use whenever you learn something during the work, about a field, a tool or why something was chosen, and whenever the user mentions the wiki. Decides whether it deserves a page, then writes it.
---

# Wiki

The wiki is where agents write down what they learn, so the user can read it and
later sessions can start from it.

It lives in `$VAULT_DIR/wiki/`, a folder of linked Markdown pages. The user's
own notes are in `$VAULT_DIR/notes/`, and on a computer with a private space
also in `$VAULT_DIR/private/notes/`. Read them when they help, and never change
them.

## Decide whether it deserves a page

Most of what you learn in a session doesn't. Write a page when what you learned
will still be true after this task, and someone working in this area later would
want to know it. Good pages explain something:

- what an experiment showed and why, such as which reward shaping made a
  reinforcement learning agent exploit the game instead of learning it
- how a tool really behaves where its docs are silent or wrong, with the version
  you checked
- a comparison you researched, and what decided it
- a decision and the reasons that would change it

Leave out what belongs elsewhere: lists of commands or projects, session logs
and task status, which go in the repository's `agent-notes/`, facts about one
repository, which go in its docs, and anything about how to work with the user,
which is memory. Never write credentials, other people's personal details or
quotes from a conversation.

## Write the page

Read `index.md` and search the wiki for the topic first. When a page already
covers it, improve that page instead of starting another. When a page is wrong,
rewrite it rather than adding an update section.

- Give each page one topic and a file name that's unique in the wiki and makes
  sense alone, such as `ppo-reward-hacking.md`, because a link is the file name
  without its folder. Put it in a folder for its subject, such as `ml/rl/` or
  `tools/rex/`, so the next project in that field finds it. Use a project
  folder, such as `projects/jace/`, only for what is about that one project,
  such as which experiments it ran and what they showed.
- Start with front matter that has `updated: YYYY-MM-DD` and `sources:`, a list
  of the links you used. Then give the page a title that states the answer, and
  answer its question in a sentence or two before the detail.
- Link another page as `[[name]]` where you first mention it. When you rename a
  page, change every link to it in the same edit.
- Add or change its line in `index.md`, grouped by folder: the link and the
  question the page answers. Add a line to the top of `log.md`: the date, the
  link and what changed.

## Commit it

In `$VAULT_DIR`, format each page you changed with the command the vault's check
prints:

```sh
uvx rumdl@0.3.2 fmt --config .rumdl.toml wiki/ml/rl/ppo-reward-hacking.md
```

The vault's `.rumdl.toml` wraps prose at 80 columns, as Neovim does when the
user saves a page. `--config` names it because `private/` is a git repository of
its own, where rumdl wouldn't find it. The vault's check refuses a page that
isn't formatted, breaks one of rumdl's lint rules or isn't linked from
`index.md`. Then commit and push only the wiki paths you changed, never the
user's notes:

```sh
git -C "$VAULT_DIR" add wiki/ml/rl/ppo-reward-hacking.md wiki/index.md wiki/log.md
git -C "$VAULT_DIR" commit -m "Explain why PPO exploited the reward"
git -C "$VAULT_DIR" push
```

The commit hook runs `bin/check.py`, which refuses two pages with the same name
and links that find no page. Fix what it reports and commit again.

## The private wiki

A computer may also have `$VAULT_DIR/private/wiki/`, which has its own git
repository and is never pushed. On such a computer, put a page in the shared
wiki only when every fact on it comes from a public source you cite, and
everything else in the private one. Commit private pages there, without pushing.
Never link from the shared wiki into the private one, because the link would
publish the private page's name.
