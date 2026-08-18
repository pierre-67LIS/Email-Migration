#!/bin/bash
# Email Migration — semi-annual controller
# Diagnostics and human-in-the-loop validation for Apple Mail migrations.
# It does NOT move or delete email automatically.

set -u

CUTOFF="${1:-2025-06-30}"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="${HOME}/Desktop/Email-Migration-Reports"
REPORT="${REPORT_DIR}/migration-${CUTOFF}-${STAMP}.txt"
MAILROOT="${HOME}/Library/Mail"

mkdir -p "$REPORT_DIR"

log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
section() { log ""; log "============================================================"; log "$*"; log "============================================================"; }
pause_gate() {
  log ""
  read -r -p "$1 [type YES to continue]: " answer
  if [ "$answer" != "YES" ]; then
    log "STOPPED by human validation gate."
    exit 2
  fi
  log "Gate approved."
}

section "EMAIL MIGRATION VALIDATION REPORT"
log "Timestamp : $(date)"
log "Host      : $(hostname)"
log "User      : $(id -un)"
log "Cutoff    : $CUTOFF"
log "Report    : $REPORT"
log ""
log "Scope: Catolica/M365 + iCloud -> Gmail archive"
log "Excluded permanently: Hotmail, Carrot"

section "1. PRE-FLIGHT"
log "macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
log "Free disk space:"
df -h "$HOME" | tee -a "$REPORT"

log ""
log "Apple Mail process:"
pgrep -fl '/Mail.app/|Mail$' 2>/dev/null | tee -a "$REPORT" || log "Apple Mail process not detected."

log ""
log "Mail data root: $MAILROOT"
if [ -d "$MAILROOT" ]; then
  du -sh "$MAILROOT" 2>/dev/null | tee -a "$REPORT"
else
  log "WARNING: Apple Mail data root not found."
fi

section "2. ENVELOPE INDEX DISCOVERY"
INDEXES=()
while IFS= read -r f; do INDEXES+=("$f"); done < <(find "$MAILROOT" -type f -name 'Envelope Index' 2>/dev/null | sort)

if [ "${#INDEXES[@]}" -eq 0 ]; then
  log "WARNING: no Envelope Index found."
else
  for f in "${INDEXES[@]}"; do
    ls -lh "$f" | tee -a "$REPORT"
  done
fi

section "3. SQLITE INTEGRITY BASELINE"
if ! command -v sqlite3 >/dev/null 2>&1; then
  log "WARNING: sqlite3 not available. Cannot run integrity check."
else
  if [ "${#INDEXES[@]}" -eq 0 ]; then
    log "No Envelope Index available for integrity test."
  else
    for f in "${INDEXES[@]}"; do
      log "Checking: $f"
      result="$(sqlite3 "$f" 'PRAGMA integrity_check;' 2>&1)"
      log "$result"
      if [ "$result" != "ok" ]; then
        log "*** GATE FAILURE: Envelope Index did not return 'ok'. ***"
        log "Do NOT start a migration until investigated."
        exit 3
      fi
    done
  fi
fi

section "4. SPOTLIGHT / SEARCH BASELINE"
log "Spotlight status for startup volume:"
mdutil -s / 2>&1 | tee -a "$REPORT"
log ""
log "Recent Mail-related Spotlight sample (diagnostic only):"
mdfind 'kMDItemContentType == "com.apple.mail.emlx"' 2>/dev/null | head -n 10 | tee -a "$REPORT"

section "5. HUMAN GATE A — APPROVE MIGRATION BATCH"
log "In Apple Mail prepare ONLY the messages whose date is on or before: $CUTOFF"
log "Source accounts in scope: Catolica/M365 and iCloud."
log "Destination: corresponding Gmail archive mailbox."
log "Prefer bounded/date-based batches."
log "Record the approximate selected message count before moving."
pause_gate "Have you verified source, cutoff, destination and batch selection?"

section "6. MANUAL TRANSFER"
log "Perform the move in Apple Mail now:"
log "  LIVE ACCOUNT -> GMAIL ARCHIVE ACCOUNT"
log ""
log "This script deliberately does not automate the mail move."
log "Wait until Apple Mail/Gmail synchronization has settled."
pause_gate "Has the Apple Mail transfer finished and synchronization settled?"

section "7. POST-TRANSFER INTEGRITY"
if command -v sqlite3 >/dev/null 2>&1; then
  for f in "${INDEXES[@]}"; do
    log "Rechecking: $f"
    result="$(sqlite3 "$f" 'PRAGMA integrity_check;' 2>&1)"
    log "$result"
    if [ "$result" != "ok" ]; then
      log "*** POST-TRANSFER GATE FAILURE. Stop and investigate. ***"
      exit 4
    fi
  done
fi

log ""
mdutil -s / 2>&1 | tee -a "$REPORT"

section "8. HUMAN GATE B — RECONCILIATION"
log "Manually verify before approval:"
log " - source reduction vs Gmail destination growth is plausible"
log " - known messages from the migrated period are searchable in Gmail"
log " - boundary messages around $CUTOFF are correct"
log " - sample attachments open"
log " - no unexpected Recovered folders/mailboxes appeared"
log " - no pending/stalled IMAP operation remains"
pause_gate "Does reconciliation pass?"

section "9. FINAL GATE"
log "Do NOT rebuild Envelope Index or Spotlight merely because a migration occurred."
log "Rebuild only if specific diagnostics demonstrate an indexing problem."
pause_gate "Do Apple Mail search, Gmail search, integrity and reconciliation all pass?"

section "MIGRATION CYCLE CLOSED"
log "Cutoff successfully validated: $CUTOFF"
log "Final report: $REPORT"
log "Keep this report as evidence/baseline for the next six-month cycle."
log ""
log "DONE."
