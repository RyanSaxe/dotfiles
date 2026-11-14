---
name: write-docs
description: Write or restructure a README and documentation pages, keeping them short and example-first. Use when creating or rewriting a README, a docs folder or a single documentation page.
---

# Write docs

Use `write-well` and `unslop` for the prose, and this skill for what to put
on each page and in what form. Write only what the reader needs to use the
project, and give each fact its most compact form.

## Choose the form

A reader learns more from one example than from a paragraph describing it.
Before writing a paragraph, check whether you can give the same facts in
less space with one of these:

| To show                 | Use                                      |
| ----------------------- | ---------------------------------------- |
| how to run or call it   | the command or code, with what it prints |
| options, fields or keys | a table                                  |
| a procedure             | numbered commands                        |
| where each file is      | a file tree                              |
| how the parts connect   | a diagram                                |
| what it looks like      | a screenshot                             |

Add prose only for what the example can't show: when to use it, what it
assumes, and why it behaves as it does.

Instead of this paragraph:

> To back up a folder, run `keep` with the folder's path. Backups go to
> `~/.keep` unless you pass `--to` with another location. `keep list` prints
> each backup's ID, and `keep restore` takes an ID and restores that backup.

write the same facts as a code block, which is shorter and can be copied:

```sh
keep ~/notes               # back up to ~/.keep
keep ~/notes --to /mnt/b   # back up somewhere else
keep list                  # print each backup's ID
keep restore 3f2a          # restore one
```

## What to cut

For each sentence, ask whether the reader would notice it missing. Cut:

- history: what the project replaced, what was tried, why it changed
- internals that don't change how the project is used, on a page that isn't
  about them
- a sentence that only restates a nearby heading, example or link
- caveats for cases the reader won't meet
- a fact that is already on another page. Link to that page instead.

## README

Write the README so that a new reader learns what the project is and how
to start using it, in about one screen:

1. A sentence or two on what it is.
2. A screenshot or the first example of use.
3. The few ideas it is built on, a line or two each.
4. The main commands or API, as a code block or a table.
5. A link to each page in `docs/`, with a few words on its topic.

Put the install steps in the README when they take a few lines, and in
`docs/` otherwise.

Write the README in the owner's voice or a neutral one, never about the owner
in the third person.

## docs/

Put the details that don't fit on one screen in `docs/`, one page per topic,
and link each page from the README. Choose topics a reader would look for in
this project. A command-line tool might have:

```text
README.md
docs/
  setup.md      # installing it
  config.md     # every option of the config file
  commands.md   # one section per command
```

Link to a reference that already exists, such as `--help` output, a schema
or the source, instead of copying it.

## Checks

Take each example from the code, and run each command you show. Check that
every link and image path resolves.

Then read the page as a newcomer would, one sentence at a time:

- Each term is explained where it first appears, such as a command's name or
  a word the project uses in its own sense.
- The thing doing each verb can do it. A file, page or folder doesn't hold,
  keep, live or want anything. Say what it contains or where it is.
- Each sentence tells the reader something they need. Cut one that only says
  what any reader would do anyway.
