---
name: brainstorming
description: Structured multi-perspective brainstorming session for exploring ideas, solutions, and approaches
---

# Brainstorming — Multi-Perspective Idea Generation

Facilitate a structured brainstorming session that explores ideas from multiple angles.

## Process

### Step 1: Frame the Problem
- Ask the user: "What are we brainstorming about?"
- Clarify the scope: Is this about architecture, features, naming, strategy, or something else?
- Set constraints: Any non-negotiables, time limits, or technical boundaries?

### Step 2: Divergent Thinking (Generate Ideas)
Generate ideas from 5 perspectives:

**Perspective 1 — The Pragmatist**
What's the simplest solution that works today? Minimal effort, maximum value.

**Perspective 2 — The Architect**
What's the "right" solution if we had unlimited time? Clean, scalable, maintainable.

**Perspective 3 — The User**
What would the end user actually want? What pain point are we really solving?

**Perspective 4 — The Contrarian**
What if we did the opposite of the obvious approach? What assumptions are we making?

**Perspective 5 — The Incrementalist**
How can we break this into the smallest possible steps? What's the MVP of the MVP?

### Step 3: Present Ideas
For each perspective, present:
- **Idea**: One-line description
- **Pros**: Why this could work (2-3 bullets)
- **Cons**: Why this might fail (2-3 bullets)
- **Effort**: Low / Medium / High
- **Risk**: Low / Medium / High

### Step 4: Evaluate and Rank
Present a comparison matrix:

| Idea | Effort | Risk | Value | Score |
|------|--------|------|-------|-------|
| Pragmatist | Low | Low | Medium | ... |
| Architect | High | Low | High | ... |
| ... | ... | ... | ... | ... |

Score = Value / (Effort + Risk)

### Step 5: Converge
- Ask the user which ideas resonate
- Combine elements from multiple ideas if useful
- Produce a recommended approach with rationale

### Step 6: Next Steps
Based on the chosen direction:
- If it's a feature → suggest `/new-feature` or `/write-a-prd`
- If it's architecture → suggest spawning `arch-reviewer` for validation
- If it needs more exploration → suggest another round of brainstorming on a specific sub-topic

## Rules
- Quantity over quality in Step 2 — filter later
- No idea is "stupid" during divergent thinking
- Always include at least one unconventional approach
- Keep each perspective to 3-5 sentences max
- Let the user drive the final decision — present options, don't prescribe
