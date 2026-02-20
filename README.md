# tomate

Multi-agent orchestration engine in MoonBit. Native port of [takt](https://github.com/nicholasgriffintn/takt).

Tomate models agent workflows as **pieces** composed of **movements** — a state machine where each movement executes an LLM call, evaluates rules against the response, and transitions to the next movement.

## Features

- JSON-driven workflow configuration
- Tag-based and AI-judge rule evaluation
- Loop detection and cycle monitoring
- Parallel, arpeggio, and team-leader execution modes (stubs)
- Claude CLI (`claude -p`) as the default provider
- Mock provider for testing

## Requirements

- [MoonBit](https://www.moonbitlang.com/) toolchain
- [just](https://github.com/casey/just) (task runner)
- `claude` CLI (for Claude provider)

## Quick Start

```bash
# Build
just build

# Run tests
just test

# Validate a config
just run validate examples/simple.json

# Run a workflow with mock provider
just run run examples/simple.json --task "build fibonacci" --provider mock

# Run a workflow with Claude
just run run examples/simple.json --task "build fibonacci"
```

## Config Format

Workflows are defined as JSON. A **piece** contains an array of **movements**, each with an instruction template, persona, and transition rules.

```json
{
  "name": "simple-workflow",
  "movements": [
    {
      "name": "plan",
      "persona": "You are a software architect.",
      "instructionTemplate": "Create a plan for: {task}",
      "rules": [
        { "condition": "plan is complete", "next": "implement" }
      ]
    },
    {
      "name": "implement",
      "instructionTemplate": "Implement the plan. Task: {task}",
      "edit": true,
      "passPreviousResponse": true,
      "rules": [
        { "condition": "done", "next": "COMPLETE" }
      ]
    }
  ],
  "initialMovement": "plan",
  "maxMovements": 10
}
```

Rules are matched by `<rule_N>` tags in the LLM response. If no tag is detected and `isAiCondition` is set, a judge LLM call evaluates the response against the condition text.

Special `next` values: `"COMPLETE"` finishes the piece, `"ABORT"` aborts it.

## Architecture

```
src/
  types/        # Core types (PieceConfig, PieceState, etc.)
  config/       # JSON parsing and builder DSL
  eval/         # Rule evaluation (tag detection, aggregates)
  instruction/  # Prompt template expansion
  prompt/       # Faceted prompt composition
  loop/         # Loop and cycle detection
  provider/     # LLM providers (Claude CLI, Mock)
  engine/       # State machine executor
  integration/  # Integration tests
  cmd/app/      # CLI entry point
```

## License

MIT
