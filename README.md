# Email Migration

Semi-annual, human-in-the-loop workflow for migrating older mail from the live **Catolica (Microsoft 365)** and **iCloud** accounts into the **Gmail archive account**, using Apple Mail as the transport UI and one controller script for the validation logic.

## Objective

Maintain Gmail as the consolidated historical corpus while keeping recent mail in the live accounts. The workflow is deliberately conservative: the controller automates the diagnostics and validation scripts; the human approves the critical gates and performs/authorizes the actual mailbox changes.

## Cadence and cutoff rule

Run approximately every six months.

- First planned run: end of December 2026
- Next: July 2027
- Next: December 2027
- Continue semi-annually

The validated historical cutoff after the August 2026 work is **2025-01-01**. Therefore the first new migration tranche is:

**2025-01-01 through 2025-06-30 inclusive**

Internally the controller treats this as the half-open interval:

`2025-01-01 <= date < 2025-07-01`

A successful cycle advances the saved state to `2025-07-01`. A failed or interrupted cycle does not advance it.

## Accounts in scope

- Catolica / Microsoft 365
- iCloud
- Gmail archive destination

Hotmail and Carrot are closed and are **not** part of future cycles.

## One controller — no manual SQL annex execution

The authoritative executable is:

`scripts/email_migration.sh`

The controller now incorporates the validation logic that had originally been written as separate Terminal/SQLite commands in the runbook annex. The Word/runbook documentation explains the logic; the controller executes it.

You should not normally need to copy/paste separate SQL validation scripts into Terminal.

## Safe test mode

Before the first live cycle, and whenever the script is changed, run:

```bash
bash email_migration.sh --dry-run
```

Dry-run mode performs the available **read-only** checks and stops automatically before the first migration gate. It does not ask you to move, copy, delete, rebuild, or reindex mail and does not advance the cutoff state.

The dry run performs:

- active Apple Mail `Envelope Index` discovery
- SQLite `PRAGMA integrity_check`
- SQLite `PRAGMA foreign_key_check`
- dynamic mailbox/account discovery; no hard-coded ROWIDs
- exact iCloud and M365 source counts for the migration window
- local Gmail `Archive - iCloud` and `Archive - Catolica` baseline counts
- Mail action-queue diagnostics when those tables exist
- Spotlight status check
- read-only Message-ID duplicate baseline for the two recurring Gmail archives
- timestamped report creation on the Desktop

The remaining pre-migration checks requiring an independent source of truth are explicitly reported as human/server checks: confirm Apple Mail Activity is idle and independently compare Gmail server label counts with the local archive counts.

## Full live workflow

1. **Gate 1 / pre-flight** — controller discovers the current Mail database and mailbox IDs, validates database health, calculates the exact source population, records destination baselines and duplicate/search context.
2. **Independent server validation** — compare `Archive - iCloud` and `Archive - Catolica` counts against Gmail server-side counts.
3. **Human approval** — approve the exact date window and populations.
4. **Apple Mail copy** — copy the approved source tranche into the corresponding Gmail historical archive in controlled/date-bounded batches. Do not delete the source yet.
5. **Gate 2 / copy reconciliation** — controller compares source messages against Gmail destination using `global_message_id` as the primary accounting key. Any unexplained missing population causes HOLD.
6. **Source cleanup approval** — only after Gate 2 passes, remove the validated source tranche from live iCloud/M365. Do not empty Bin/Deleted Items yet.
7. **Gate 3 / post-deletion reconciliation** — controller verifies that the migrated window no longer remains in live Inbox/Sent and that the Gmail archive remains intact.
8. **Permanent source cleanup** — only after Gate 3, empty the relevant Bin/Deleted Items and allow synchronization to finish.
9. **Restart/final checkpoint** — clean quit/restart after the substantial migration, then final local integrity checks.
10. **Gate 4 / server ↔ Apple Mail** — independently confirm exact Gmail server/local archive-count agreement.
11. **Duplicate audit** — read-only; small stable duplicate residue is accepted rather than cosmetically cleaned.
12. **Search integrity** — known subject and body-only searches in both newly updated archives. Do not rebuild indexes unless a controlled search fails.
13. **Close cycle** — only after all gates pass does the controller advance its saved cutoff to the next six-month boundary.

## Failure policy

- **Beginning-of-batch stall:** first determine whether the transfer actually started. Check server/log behavior and stale local user-initiated actions before restarting blindly.
- **Mid-batch stall:** assume partial progress is possible. Establish what reached Gmail before retrying and avoid duplicating the whole batch.
- Check Gmail/server evidence before blaming Apple Mail indexes.
- Never delete source mail merely because the destination visually appears populated. Source deletion comes only after reconciliation.
- Do not rebuild Envelope Index or Spotlight as a reflex. Healthy indexes can coexist with an IMAP transfer problem.
- SQLite is primarily a read-only diagnostic/reconciliation tool here. Database repair is last resort and requires backup plus explicit post-repair integrity checks.

## Reports and state

Reports are written to:

`~/Desktop/Email-Migration-Reports/`

The successful cutoff state is stored under:

`~/Documents/Email-Migration/state.txt`

The initial default state is `2025-01-01` until the first future cycle successfully closes.

## Repository structure

- `README.md` — operating model and controller behavior
- `scripts/email_migration.sh` — authoritative semi-annual controller
- `docs/VALIDATION-GATES.md` — human gate criteria and operational checklist

## First future tranche

**1 January 2025 through 30 June 2025 inclusive**, planned for the end of December 2026.
