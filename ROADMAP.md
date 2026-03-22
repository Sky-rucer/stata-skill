# Roadmap

Big-picture directions for improving the skill. These are open problems, not specifications — if you have ideas on any of them, open an issue or PR.

This is also a good place to learn about building Claude Code skills. The problems below — how to test documentation quality, how to structure reference material for agents, how to give agents dynamic access to help systems — apply to skill development in general, not just Stata.

## Real-world empirical test suite

The current tests are synthetic prompts. But there's a huge amount of publicly available empirical work — published papers with replication data, public-use datasets, well-known textbook exercises. A stronger test suite would hand the agent a real dataset and a real task (e.g., replicate the core specification from a paper). The goal isn't perfect replication — there will always be variation. The goal is: can the agent find the right tools, write code that actually runs, and get in the ballpark? That's what tells you whether the documentation is doing its job.

## Leaner reference files and deeper progressive disclosure

The reference files are comprehensive, which may or may not be a good thing. They contain information that's irrelevant to most queries, and there's evidence that extra context can hurt rather than help — the model sometimes cargo-cults patterns it doesn't need. Worth exploring whether the files could be made more minimal, or whether progressive disclosure could go further, letting agents navigate to just the section they care about rather than reading the whole file.

## Dynamic help file access

Stata has built-in help files for every command, but they're long and in an ugly format (SMCL). Right now the skill can't use them. Inspired by [@SebastianSardon](https://x.com/SebastianSardon/status/2035218637812806117) and consistent with the [openclaw](https://github.com/anthropics/claw) CLI philosophy: instead of pre-documenting every command, give the agent a way to query help dynamically, in a clean format, at the right granularity. Think of how a good CLI help system works — a top-level overview when you ask broadly, and the ability to drill into specific sub-options when you need detail.
