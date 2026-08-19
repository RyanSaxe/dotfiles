# Verification

Verification answers one question: what evidence shows that the change works
where a person will actually encounter it?

Automated checks establish useful facts, but a passing test suite is not the
same as a working feature. Verify through the public interface whenever
practical: run the command, use the UI, load the configuration with its real
consumer, or call the library as a downstream user would.

## Match the effort to the change

Choose the depth from the change's risk, novelty, uncertainty, and consequence.

- A small, familiar change may need one direct confirmation on the driver's
  machine.
- A normal feature should exercise the intended path and the most important
  failure or boundary.
- A new, visual, stateful, or high-risk feature deserves realistic exploratory
  use. Try alternate paths, repeat actions, and transitions that could expose
  hidden state.

Do not follow a fixed checklist when it produces weak evidence. Prefer the
shortest path to convincing evidence.

## Verify the experience

Start from the outcome the driver requested, not from the files that changed.
Use the feature as its user would and observe both the intended result and
important side effects. For a defect, reproduce the failure when practical and
show that the same path now succeeds.

When direct use is impossible, use the closest realistic simulation and state
what the gap leaves unproven. Screenshots, recordings, logs, or saved output are
valuable when the result is visual, environmental, or otherwise difficult to
inspect from a command result alone.

## Report evidence

Describe what you exercised and what you observed. Distinguish direct evidence
from inference, and identify relevant behavior that was not verified. Never
describe a check as proving more than it actually does.
