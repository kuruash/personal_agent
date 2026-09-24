# Personal AI Evaluations

## Purpose

`evals/` contains version-controlled AI quality evaluation datasets for Personal AI.

## Difference from Tests

`macos/Tests/` tests deterministic software correctness. `evals/` tests AI and agent quality and behavior.

## Dataset

`datasets/personal_ai_profile_v1.jsonl` is the Profile V1 baseline dataset. Each non-empty line is one independent JSON example.

## Schema

- `inputs` contains the user message.
- `reference.expected_facts` lists facts a grounded answer should include.
- `reference.expected_behavior` describes acceptable response behavior.
- `reference.tool_expectations` records acceptable tool-routing expectations.
- `reference.must_not` lists prohibited claims or behaviors.
- `metadata` identifies and classifies the example.

## Tool Semantics

- `preferred` lists the cleanest or most efficient tool choices.
- `allowed` lists other valid choices that can still produce a correct answer.
- `forbidden` lists tools that should not be needed or indicate incorrect capability routing.

## Important

This dataset has not yet been wired to evaluators or experiments.
