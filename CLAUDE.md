# CLAUDE.md

## Code review (agent-review)

PRs here are reviewed with the agent-review plugin, run locally from Claude Code. CI does not review PRs, and teammates don't review each other's PRs: the bot's approval is the review.

1. Push the branch and open the PR. The review reads what is on GitHub, not unpushed work.
2. Run `/agent-review:review`, or `/agent-review:yolo-review` to fix every blocker and wait for the approval.
3. Fix or dismiss each finding with `/agent-review:address fix 1,2 dismiss 3 [false-positive]: <reason>`, then run `/agent-review:re-review`.
4. When no blocker (severity 7+) is open, the `github-actions` bot approves the PR.

- A PR labeled `needs-human-approval` needs a person's approval. The card-data check adds the label, and so does any path under `human_approval` in `.claude/review/config.yml`.
- Never edit `.claude/review/` rules or config to get a PR to pass; change them in their own PR. The address step commits `.claude/review/learnings/feedback.jsonl` when you fix or dismiss a finding, and that's expected. The review's metrics and the learning loop's scratch files (`learnings/pending/`, `learnings/findings.json`) are gitignored; never commit them, since any commit of them on a PR branch takes back the bot's approval (see the next bullet). `feedback.jsonl` is marked `merge=union`, which settles a local merge of two appends; the withdraw job rebuilds a merge of master without merge drivers, so a PR whose `feedback.jsonl` changed on both sides still needs a re-review after merging master in.
- A new push takes back the bot's approval unless it only merges in the default branch. Run the review again to get it back.
- Needs agent-review plugin 1.1.0 or later: `/plugin marketplace update cruglobal`.
