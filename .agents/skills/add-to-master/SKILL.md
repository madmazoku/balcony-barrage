---
name: add-to-master
description: Publish accepted Godot changes through AI-N branch, GitHub PR and merge into master.
---

# Add to Master — Balcony Barrage
Adapted from G:/Git/media_mcp/.agents/skills/add-to-master/SKILL.md.

## Acceptance and scope
Owner must explicitly accept the phase before publishing its implementation. Keep unaccepted work on its feature branch. Preserve unrelated changes. The initial empty-project bootstrap is the only direct initial master commit.
Read AGENTS.md and ROADMAP. Confirm root, branch, remote and status. Inspect tracked/untracked diff, identify task files. Verify gh auth, fetch metadata. Determine next unused AI-N from local/remote branches and merged PR titles. Reserve a short AI-N-slug branch from current master before implementation. Never discard/stash user work automatically.

## Prepare accepted release
Use metadata derived from the current diff. Branch AI-N-short-slug, commit and PR title AI-N: concise description. Body explains resulting behavior, verification and known limitations.
Update README for changed setup/options/workflows. Set application/config/version in project.godot to 0.N.0 and finalize matching CHANGELOG section with date and AI-N. Update ROADMAP with owner acceptance evidence. Do not create Python version files.
Run the README headless import and foundation validator after version synchronization. Run normal gameplay/manual checks for the changed behavior when gameplay exists. Run existing regression checks relevant to the phase. Never claim device checks that were not performed. Fix failures before commit.
Stage explicit paths only. Review git diff --cached --name-status, full staged diff and git diff --cached --check. Exclude cache, builds, credentials, checkpoints, LoRA and rejected media. Include accepted game assets and their provenance.

## Publish
Commit, push feature branch with upstream. Check for an existing PR before creating one. Open PR into master using gh. Use a body file for multiline descriptions.
Merge using gh pr merge NUMBER --merge. Preserve remote source branch, never use --delete-branch or a local merge commit. Repository delete_branch_on_merge must be false or report inability to guarantee preservation.
Switch master and pull origin master. Verify merged PR, local merge commit, retained remote feature branch and preserved unrelated work.
Report branch, commit, PR link, master commit and intentionally unstaged files.
If auth, protections, conflicts or checks block progress, preserve work and report the exact blocker.
