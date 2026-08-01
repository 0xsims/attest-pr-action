# Rubric Attest PR

Every AI-authored pull request in your repo carries a sealed, independently verifiable provenance record.

**What gets sealed:** repo, PR number, base/head SHAs, SHA3-256 of the full diff, agent identity, model, CI run ID, timestamp — signed with ML-DSA-65 (FIPS 204 post-quantum) and Merkle-anchored to Hedera public ledger.

**Why:** when agents open PRs autonomously, "who wrote this and what exactly did they change" becomes an audit question. Git history is mutable; force-pushes and rebases rewrite it. The attestation record survives independently of the repo.

**Verify without trusting us:** every PR comment includes a public verify URL. The record is checkable against the public ledger by anyone.

## Setup
1. Get a free API key at https://rubric-protocol.com (Developer tier: 1K attestations/mo)
2. Add it as repo secret `RUBRIC_API_KEY`
3. Add the workflow (see `.github/workflows/example.yml`)

Free tier covers ~30 AI PRs/day. Standard tier for fleets.

## Behavior on quota exhaustion
If your key's monthly quota is exhausted, the Action logs a warning and exits cleanly — it will never fail your PR checks over a quota wall. Attestation resumes automatically next cycle.
