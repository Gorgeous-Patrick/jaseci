# GitHub Actions Workflows

This directory contains GitHub Actions workflows for the Jaseci repository.

## Workflows

### Sync Fork with Upstream (`sync-fork.yml`)

Automatically synchronizes the fork with the upstream repository (jaseci-labs/jaseci).

**Schedule**: Daily at 2 AM UTC

**Trigger**:
- Scheduled: Runs automatically every day at 2 AM UTC
- Manual: Can be triggered manually via workflow_dispatch

**What it does**:
1. Fetches the latest changes from upstream (jaseci-labs/jaseci)
2. Merges upstream/main into the fork's main branch
3. Pushes the updated main branch to the fork
4. Creates a summary of the sync operation

**Note**: If merge conflicts occur, the workflow will fail and manual
resolution is required. In that case:
1. Clone the repository locally
2. Add upstream remote: `git remote add upstream https://github.com/jaseci-labs/jaseci.git`
3. Fetch upstream: `git fetch upstream`
4. Merge and resolve conflicts: `git merge upstream/main`
5. Push changes: `git push origin main`

### Deploy Documentation (`deploy-docs.yml`)

Builds and deploys the jac-lang.org documentation website.

**Schedule**: Daily at 2 AM UTC, on releases, and on push to main

### Test Workflows

- `test-jaseci.yml`: Runs tests for the main jaseci packages
- `test-jac-scale.yaml`: Runs tests for jac-scale package

### Release Workflows

- `release-jaclang.yml`: Release workflow for jaclang package
- `release-byllm.yml`: Release workflow for jac-byllm package
- `release-client.yml`: Release workflow for jac-client package
- `release-scale.yml`: Release workflow for jac-scale package
- `release-streamlit.yml`: Release workflow for jac-streamlit package
- `release-jaseci.yml`: Release workflow for jaseci package
- `release-github.yml`: Create GitHub releases for specific subdirectories
