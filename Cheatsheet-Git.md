# Cheatsheet: Git

Paste-ready git commands for `opda-ops` and its sibling repos.

## Untrack a gitignored file committed before the ignore rule

Keeps the file on disk; stops tracking it.

```bash
git -C opda-ops rm --cached scripts/.env.dev && git -C opda-ops commit -m "Untrack scripts/.env.dev (gitignored placeholder env)"
```

## Verify what is still tracked under a directory

```bash
git -C opda-ops ls-files scripts/ | grep -i env
```
