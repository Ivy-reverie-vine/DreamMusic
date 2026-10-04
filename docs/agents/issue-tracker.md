# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number,title,body,labels: [.labels[].name],comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`.
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` or `gh issue edit <number> --remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`.

Infer the repository from the GitHub remote; run commands inside this clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** External pull requests are not part of the issue triage queue by default.

## When a skill says “publish to the issue tracker”

Create a GitHub issue and apply the requested triage label.

## When a skill says “fetch the relevant ticket”

Run `gh issue view <number> --comments`.
