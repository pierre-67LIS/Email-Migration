# Email Migration

Semi-annual, human-in-the-loop workflow for migrating older mail from the live **Catolica (Microsoft 365)** and **iCloud** accounts into the **Gmail archive account**, using Apple Mail as the migration UI.

## Objective

Maintain Gmail as the consolidated historical corpus while keeping recent mail in the live accounts. The workflow is deliberately conservative: automation prepares and validates; the human approves each gate and performs/authorizes the migration.

## Cadence and cutoff rule

Run approximately every six months.

- First planned run: end of December 2026
- Next: July 2027
- Next: December 2027
- Continue semi-annually

The previous completed migration used **pre-2025** as the cutoff. Therefore the first new cycle advances the cutoff to **30 June 2025**. The general rule is to advance the archive boundary by roughly six months per cycle.

## Accounts in scope

- Catolica / Microsoft 365
- iCloud
- Gmail archive destination

Hotmail and Carrot are closed and are **not** part of future cycles.

## Operating principle

Do not treat Apple Mail drag-and-drop as an unvalidated clerical operation. Each migration is a controlled batch with baseline, transfer, reconciliation, and final integrity gates.

The process is designed around lessons learned during the August 2026 migration: large IMAP operations can stall; a beginning-of-batch stall differs from a mid-batch failure; Gmail server state/logs matter; Apple Mail search can be fuzzy; and local index health must be separated from server-transfer health.

## Run sequence

1. **Pre-flight / no changes** — confirm Apple Mail is stable, accounts online, Gmail reachable, and no existing migration operation is running.
2. **Baseline** — run the validation script and save its report before moving anything.
3. **Define batch** — select messages in the source account whose sent/received date is at or before the current cutoff. For the first cycle: through 30 June 2025.
4. **Human Gate A** — inspect the proposed batch, date limits and counts. Do not migrate until approved.
5. **Transfer** — in Apple Mail, move the approved messages from the live account to the appropriate Gmail archive mailbox. Prefer bounded/date-based batches rather than one enormous operation.
6. **Observe** — allow Apple Mail and Gmail to complete synchronization. A UI count alone is not proof of completion.
7. **Post-transfer validation** — rerun validation and reconcile source reduction against destination growth.
8. **Human Gate B** — investigate discrepancies, stalls, missing messages, unexpected recovered folders, or count mismatches before continuing.
9. **Integrity validation** — check Apple Mail's Envelope Index/database health and Spotlight/search health. Rebuild indexes only when evidence justifies it; do not rebuild routinely after a successful migration.
10. **Human Gate C / close** — confirm the migrated date range is searchable in Gmail, source/destination reconciliation is acceptable, and no pending IMAP work remains. Save the final report as the baseline for the next cycle.

## Failure policy

- **Beginning-of-batch stall:** first suspect stale/local user-initiated state or a transfer that never actually started. Stop, verify state, and retry a smaller clean batch.
- **Mid-batch stall:** assume partial progress is possible. Do not blindly repeat the whole batch; determine what reached Gmail first.
- Check Gmail/server evidence before blaming Apple Mail indexes.
- Never delete source mail merely because the destination visually appears populated. Deletion/move completion must follow reconciliation.
- Do not rebuild Envelope Index or Spotlight as a reflex. We established in August 2026 that healthy indexes can coexist with an IMAP transfer problem.

## Automation boundary

The controller in `scripts/` is intended to automate diagnostics, baseline capture, cutoff calculation, report generation and validation checks. Actual destructive/mutating mail operations remain behind explicit human validation gates.

## Repository structure

- `README.md` — operating procedure and decision rules
- `scripts/email_migration.sh` — semi-annual controller / validation workflow
- `docs/VALIDATION-GATES.md` — detailed checklist and gate criteria

## Next cutoff

**30 June 2025** for the first semi-annual run at the end of December 2026.
