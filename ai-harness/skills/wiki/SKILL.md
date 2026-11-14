---
name: wiki
description: Keep the user's wiki, the Markdown pages in their vault that agents write and the user reads. Use when you find something worth reusing in later work, such as how a tool behaves, a researched comparison or a decision and its reasons, and when the user asks you to record, find or tidy something in the wiki.
---

# Wiki

The wiki is a folder of linked Markdown pages in `~/generic/vault/wiki/`.
Agents write it and the user reads it. Write only inside a wiki folder. Read
the user's own notes in `notes/` when they help, but never change them. Never
run git in the vault. The user commits and pushes it.

## Which wiki

A computer may also have a private wiki in `~/generic/vault/private/wiki/`,
which is never pushed anywhere. On such a computer, put a page in the shared
wiki only when every fact on it comes from a public source you cite, such as
a project's documentation or a public repository. Put everything else in the
private wiki. On a computer without a private wiki, use the shared one.

## What goes in

Write a page when you find something another session could reuse:
how a tool or library behaves, a comparison you researched, or a decision
and its reasons. Leave out:

- session logs, plans and task status, which go in the repository's
  `agent-notes/` folder;
- facts about one repository, which go in that repository's docs, linked
  from the wiki;
- credentials, other people's personal details and quotes from a
  conversation.

## Find the page first

Read `index.md`, then search the wiki for the topic. When the wiki already
has a page on it, update that page instead of starting another one.

## Pages

- Give each page one topic and a file name that is unique in the wiki and
  makes sense alone, such as `rex-hosts.md`, because a link is the file name
  without its folder.
- Put each page in a folder for its topic, nested as deep as you like, such
  as `tools/rex/`. Move pages into a better folder whenever you see one. A
  move doesn't break links.
- When you rename a page, change every `[[old-name]]` in the wiki to
  `[[new-name]]` in the same edit.
- After you add, move or rename pages, run `~/generic/vault/bin/check`. It
  reports two pages with the same name and links that find no page.
- Start a page with two lines, `updated: YYYY-MM-DD` and `sources:` with
  the links you used, then the answer to the page's question in a sentence
  or two. Name the version you checked a tool against.
- Link another page as `[[name]]` where you first mention it.
- Never link from the shared wiki into the private one, because the link
  would push the private page's name.
- When a page is wrong, rewrite it. Don't add an "Update" section.

## index.md and log.md

In `index.md`, write one line per page, grouped by folder: the link and the
question the page answers. Change it whenever you add, move or rename a page.

In `log.md`, add one line per change, newest first: the date, the link and
what changed.
