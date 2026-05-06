# Architecture Decision Records

Records of significant architectural decisions. These prevent re-litigating settled questions.

## Format

Each ADR is a markdown file: `NNNN-short-title.md`. Use the template:

```markdown
# NNNN: Title

**Status:** accepted | superseded by NNNN | deprecated
**Date:** YYYY-MM-DD

## Context
What prompted this decision?

## Decision
What did we decide?

## Consequences
What follows from this decision — both good and bad?
```

## Index

- [0001: Notifications for cross-view communication](0001-notifications-for-cross-view-comms.md) — **superseded by 0003**
- [0002: AttentionManager lives in Features/Attention](0002-attention-manager-in-app-layer.md) — **resolved**
- [0003: Unified command dispatch via AppCommand + AppState](0003-unified-command-dispatch.md)
