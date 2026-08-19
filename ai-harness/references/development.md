# Development Practices

Use this guide when designing or implementing substantial changes. It describes
engineering judgment, not a required sequence of ceremonies.

## Design from the interface

When an important public, user-facing, or cross-component interface is part of
the work, align on the interface before implementation. Make the behavior,
inputs, outputs, and meaningful failure cases clear enough that tests and
documentation can describe the same contract.

For internal changes, start from the existing contracts and patterns. Do not
invent a new interface merely to make a local implementation feel cleaner.

## Keep code legible

Prefer names, types, and structure that make intent apparent. Keep control flow
flat enough to follow, and keep functions and modules focused on one coherent
responsibility. Prefer composition and clear boundaries when they reduce
coupling; do not apply either as a slogan.

Use comments for reasons the code cannot express: constraints, invariants,
workarounds, or decisions that would otherwise be surprising. Do not use
comments to narrate straightforward code or to compensate for unclear names
and structure.

## Keep boundaries honest

Minimize coupling between components and depend on stable contracts rather than
incidental implementation details. Do not add abstractions, configuration, or
fallback paths for hypothetical callers. A small amount of duplication can be
healthier than a shared abstraction that couples unrelated behavior.

When required inputs, dependencies, or environment assumptions are missing,
fail clearly and as close to the boundary as practical. Do not catch or hide an
error merely to keep the process moving unless recovery is an intentional part
of the behavior.

## Optimize for the real use

Do not optimize based on intuition or isolated microbenchmarks. First make the
behavior correct and understandable. When performance matters, measure the
realistic workload and let that evidence guide the change.

## Leave the code easier to change

Prefer designs that reduce future cognitive load. Remove complexity introduced
by the change, preserve useful local conventions, and avoid turning unrelated
technical debt into the scope of the current task.
