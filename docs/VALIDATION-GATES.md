# Validation Gates

This checklist is the operational control sheet for each six-month migration.

## Gate 0 — Pre-flight

**No mail moves yet.**

- [ ] Apple Mail launches normally and is not already performing a large move/copy.
- [ ] Catolica/M365, iCloud and Gmail archive accounts are online.
- [ ] Gmail archive mailboxes are visible.
- [ ] Mac has sufficient free disk space.
- [ ] Current cutoff is explicitly recorded.
- [ ] A baseline report has been saved.

**First December 2026 cycle cutoff: 2025-06-30.**

Proceed only if the environment is stable.

## Gate A — Batch approval

Before dragging/moving messages in Apple Mail:

- [ ] Source account is correct: Catolica/M365 or iCloud.
- [ ] Selection contains only messages at/before cutoff.
- [ ] Approximate selected count is recorded.
- [ ] Destination is the intended Gmail archive mailbox.
- [ ] Batch size is reasonable; use smaller/date-based batches if necessary.
- [ ] No Hotmail or Carrot migration is included.

**Human action:** approve the batch, then perform the Apple Mail move from the live account to the Gmail archive account.

## Gate B — Transfer reconciliation

After Apple Mail appears to have completed:

- [ ] Wait for account synchronization to settle.
- [ ] Destination count/growth is plausible relative to source reduction.
- [ ] Search Gmail for several known messages from the migrated period.
- [ ] Check oldest/newest boundary messages around the batch dates.
- [ ] Confirm attachments on a small sample can be opened.
- [ ] Look for unexpected recovered mailboxes/folders.
- [ ] Run post-transfer validation report.

### If the transfer stalls

**At the beginning:** do not assume any meaningful server progress. Cancel/stop safely, verify state, and retry a smaller clean batch.

**Mid-batch:** assume partial progress. Establish what reached Gmail before retrying. Avoid duplicating the entire batch.

Do not jump directly to index rebuilding. First distinguish IMAP/server transfer problems from local search/index problems.

## Gate C — Local integrity and search

- [ ] Locate Apple Mail Envelope Index files.
- [ ] Run SQLite `PRAGMA integrity_check` on the active Envelope Index.
- [ ] Result is `ok`.
- [ ] Spotlight metadata service is operational.
- [ ] Apple Mail search returns representative migrated messages.
- [ ] Gmail-side search returns representative migrated messages.

A successful migration does **not** require routine index rebuilding. Rebuild only if diagnostics show corruption or persistent indexing failure.

## Gate D — Close cycle

- [ ] All approved batches for both active source accounts are complete.
- [ ] No unresolved discrepancy remains.
- [ ] No large pending IMAP operation remains.
- [ ] Final validation report saved.
- [ ] New archive cutoff recorded as the baseline for the next cycle.

Do not start the next six-month boundary until this gate is closed.
