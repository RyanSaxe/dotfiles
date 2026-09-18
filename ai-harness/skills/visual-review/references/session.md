# Run the session

Resolve commands relative to the skill directory. Keep the session directory in
the conversation so an interrupted turn can resume it.

Start the helper through a long-running tool process, from inside the
repository the user is asking about:

```sh
node scripts/session.mjs start
```

It prints `sessionId`, `sessionDir`, `origin`, `url`, and `repo`. Keep the
directory and the URL in the active conversation; every other command requires
`--session-dir PATH`. Open the URL in the user's default browser and give them
the link in chat: macOS `open`, Windows PowerShell `Start-Process`, Linux
`xdg-open`, passing the URL as a quoted argument. Report a failed launch and
keep the link available. Do not open a new tab on each page.

If a session already exists, resume it rather than creating a replacement.
While its helper is still running, every command below works against it
with `--session-dir PATH`; `start --session-dir PATH` is for a helper that
stopped, and it refuses while the owner is alive. After an abnormal
shutdown, inspect the recorded owner before using `--recover-lock`; do not
delete ownership files blindly. The session id is the directory's name.

## The wait loop

```sh
node scripts/session.mjs wait --session-dir PATH --timeout 55
```

<important>

Keep the agent turn waiting for the life of the session. A timeout is not
completion; wait again. A side question does not end the session: answer it,
then resume the same wait. The helper records questions but cannot wake an
ended turn. If the conversation is interrupted, the next turn resumes the
explicit session and reads its queue.

</important>

When an event arrives, read its payload and acknowledge it by id:

```sh
node scripts/session.mjs ack --session-dir PATH --id EVENT_ID
```

`wait` returns the next unread event and does not acknowledge it. `ack` is
idempotent. Do not acknowledge an event you have not read.

## Answering

Read the repository first, then declare the outline, then write the pages one
at a time. See [protocol.md](protocol.md) for the commands and
[answering.md](answering.md) for what belongs on a page.

Stop only when the user says the session is finished, or when they pause,
cancel, or redirect the task. Leave the export and the session directory in
place when the helper stops.

## Limits worth knowing

The helper serves committed content only. Uncommitted edits, untracked files,
and ignored directories do not exist to it, and the app says so in its header
when the ref is a branch. It never writes to the repository except one ref
under `refs/visual-review/` when a pull request is named.

`connection.json` holds the agent token and is private to the agent. The
browser needs only the session identity. Different sessions share nothing.
