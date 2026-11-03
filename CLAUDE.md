# CLAUDE.md

## Code review (agent-review)

PRs here are reviewed with the agent-review plugin, run locally from Claude Code. CI does not review PRs, and teammates don't review each other's PRs: the bot's approval is the review.

1. Push the branch and open the PR. The review reads what is on GitHub, not unpushed work.
2. Run `/agent-review:review`, or `/agent-review:yolo-review` to fix every blocker and wait for the approval.
3. Fix or dismiss each finding with `/agent-review:address fix 1,2 dismiss 3 [false-positive]: <reason>`, then run `/agent-review:re-review`.
4. When no blocker (severity 7+) is open, the `github-actions` bot approves the PR.

- A PR labeled `needs-human-approval` needs a person's approval. The card-data check adds the label, and so does any path under `human_approval` in `.claude/review/config.yml`.
- Never edit `.claude/review/` to get a PR to pass. Change the rules in their own PR.
- Needs agent-review plugin 1.1.0 or later: `/plugin marketplace update cruglobal`.
