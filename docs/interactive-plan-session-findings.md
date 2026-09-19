# Interactive-plan session findings

Status: investigation handoff

Date: 2026-09-19

This note records the behavior, evidence, and design directions found while
reviewing the interactive-plan session protocol. It is intended to let another
agent continue the work without relying on the original conversation.

## Summary

The review tool has three related weaknesses:

1. Polling is described as a mandatory loop, but the helper and runtime do not
   enforce that loop or wake an agent after its turn ends.
2. `Agreed` is always visible in the browser, but agreement records are
   optional and the workflow does not require the agent to reconcile them.
3. The working card displays the latest progress snapshot, not a history of
   work. It assumes one active task and can jump over several updates.

The common cause is that important workflow state lives in instructions and
model memory rather than in a protocol the session can validate.

## Polling and interrupted turns

The skill says that every active-review turn ends with `wait` or `complete`.
It also says that a timeout is not completion, that side questions must be
answered before waiting again, and that an interrupted wait must resume on the
same session. See [SKILL.md](../ai-harness/skills/interactive-plan/SKILL.md)
and [session.md](../ai-harness/skills/interactive-plan/references/session.md).

Those rules are prompt guidance, not runtime enforcement.

The `wait` command polls for a finite period and returns `{"waiting": true}`
when no event arrives. The model must decide to invoke `wait` again. A tool
timeout, an interrupted turn, context compaction, or a side question can leave
the session without another poll. The helper cannot wake an ended model turn.

The hub records the last agent request as `agentSeenAt` and reports the session
as disconnected after the configured silence period, which defaults to fifteen
minutes. This detects a stopped poll late; it does not prevent or repair one.

### Direction

Make the wait result an explicit continuation protocol. A timeout should return
structured state such as:

```json
{
  "status": "waiting",
  "nextAction": "wait",
  "mustContinue": true
}
```

An event should identify the next required action, such as reading and
acknowledging the submission. The skill should say that `mustContinue` forbids
a user-facing response and requires the named action.

This should be treated as a mitigation. A tool result is still lower priority
than a system instruction, so a real guarantee requires runtime support for a
long-lived wait, automatic continuation, or a supervisor that can resume the
agent when feedback arrives.

After any interruption, the resume path should be mechanically obvious:

```text
status → wait for the next unread event → read the payload → ack → work → wait
```

## Agreed is visible but not required

The planning guidance says that exploration settles open decisions and that
Agreed holds the settled decisions with exact sources. It also says to reopen
only affected agreements and to remove a resolved question from the same page
in the next revision. See [planning.md](../ai-harness/skills/interactive-plan/references/planning.md).

The artifact contract, however, defines `agreements` as optional. The publisher
validates agreement records only when the manifest supplies them. It does not
require an agreement array, require a nonempty record, or require an agreement
reconciliation before publication. See
[authoring.md](../ai-harness/skills/interactive-plan/references/authoring.md)
and `scripts/session.mjs`.

The browser creates a built-in Agreed page when the artifact has no authored
page with that ID. When the agreement array is empty or absent, that page says
that no agreements have been recorded. The page's existence therefore does not
prove that the agent used it.

Browser choices and comments do not become agreements automatically. The agent
must interpret the submission, decide whether the topic is settled, and author
or update a stable agreement record with source references. This is the right
behavior for avoiding false agreements, but the current workflow does not force
the interpretation step.

The progress example includes `Update Agreed`, but progress steps are
agent-defined. The hub accepts any valid step names and does not require that
step, require it to be completed, or gate publication on it.

### History finding

The agreement feature itself was not recently deleted. The renderer, schema,
source resolution, and navigation remain present.

The stronger operational wording appears in commit `58820fb`, which told the
agent to keep answered choices on Agreed, preserve agreement IDs, and update
only affected entries. By `0a28fa7`, the workflow had been reduced mainly to
the more abstract statement that settled decisions belong on Agreed. The later
documentation cleanup in `9f8bf99`, followed by `9be0700`, kept the concept but
did not restore a mandatory reconciliation step.

The likely regression is therefore one of prominence and enforcement, not a
removed implementation.

### Direction

Use a mandatory `Reconcile Agreed` milestone on every revision. It should mean:

- read the feedback and conversation;
- preserve existing agreement IDs;
- add newly settled decisions;
- update decisions whose settled wording changed;
- mark decisions reopened or retired when appropriate;
- explicitly record that Agreed was checked when nothing changed.

`Update Agreed` implies that every revision changes something. `Reconcile
Agreed` covers both change and no-op cases and should be required before
publication. Whether the publisher should also require an `agreements` array,
possibly empty on the first exploration revision, remains a design choice.

## Working-card progress

The hub stores progress as a list of titles with a boolean `done` value. The
browser derives the active task as the first unfinished item. It cannot show
multiple active tasks, ownership, task start time, completion time, blocked
state, or evidence.

The browser polls status every 1.5 seconds, but the hub retains only the latest
progress snapshot. Several rapid `progress --done` calls can therefore be
coalesced into one visible jump. The agent may also batch calls while doing
work. The current interface cannot distinguish those cases.

The current model is useful for a short serial checklist. It is not a reliable
record of what an agent was doing, and it cannot represent parallel work.

### Direction

Separate receipt, work declaration, and work events:

1. `ack` records immediate receipt of the submission.
2. The coordinator declares a work graph or milestone list immediately.
3. Task transitions record meaningful events with an owner and timestamps.
4. The browser renders all active tasks and the latest event, rather than
   deriving one active task from the first incomplete row.

Useful task states are `queued`, `active`, `done`, and `blocked`. The UI does
not need every shell command. It does need enough history to explain why a
task changed and when the agent last checked in.

## Subagents

Parallel subagents can make independent investigation faster and make the work
breakdown clearer, but one coordinator must own the live session.

Good subagent tasks are bounded, mostly read-only investigations such as:

- inspecting separate code paths;
- checking independent visual or documentation concerns;
- analyzing different portions of submitted feedback;
- comparing implementation options with explicit evidence.

Subagents should return findings to the coordinator. They should not directly
acknowledge feedback, mutate the shared artifact, update Agreed, publish, or
poll the session. Parallel writes would race, and the current progress model
has no owner or merge semantics.

Each subagent can receive the relevant plan snapshot, user intent, constraints,
and an exact output contract. It does not need the entire conversation when its
task is genuinely isolated. It does need the broader context when deciding
whether a choice is settled or belongs in Agreed.

The intended flow is:

```text
acknowledge receipt
→ declare work graph
→ investigate independent tasks in parallel
→ coordinator merges findings
→ reconcile Agreed
→ check and publish
→ wait
```

Do not parallelize the final synthesis, agreement reconciliation, or publication
until the session model gives those operations one clear owner.

## Open design questions

1. Can the agent runtime support a long-lived wait or automatic continuation,
   or must the helper remain a finite polling command?
2. Should a timeout result carry `nextAction` and `mustContinue` fields, and
   should event results carry a required next action as well?
3. Should the publisher require an `agreements` array on every exploration and
   final-plan artifact, with an empty array allowed before the first decision?
4. Should publication require a completed `Reconcile Agreed` milestone?
5. Should progress become an append-only event stream, or should the hub keep
   a bounded event history alongside the current task snapshot?
6. What is the smallest useful subagent contract for isolated investigation,
   including context, output format, ownership, and failure handling?
7. Which progress states and timestamps make the working card useful without
   turning it into a transcript of internal tool calls?

## Suggested implementation order

1. Define the session state machine and continuation contract for `wait`,
   interruption, and explicit stop.
2. Make Agreed reconciliation an explicit required milestone and decide the
   artifact validation rules for `agreements`.
3. Replace the boolean-only progress snapshot with task ownership, statuses,
   timestamps, and a small event history.
4. Add coordinator-owned subagent support for bounded investigations.
5. Exercise the live browser flow, including an interrupted wait, a side
   question, a no-op Agreed reconciliation, several rapid task updates, and
   parallel active tasks.

This is an investigation note, not an implementation approval. It records the
problems and candidate directions that the next agent should turn into a
reviewed design before changing the session protocol.
