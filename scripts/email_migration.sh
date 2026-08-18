#!/bin/bash
# Email Migration — semi-annual controller
# One entry point for baseline, reconciliation, duplicate and search-integrity preparation.
# Apple Mail remains the transport UI; destructive mail actions stay behind human gates.

set -u

MODE="full"
END_INCLUSIVE="2025-06-30"
START_CUTOFF=""

usage() {
  cat <<'EOF'
Usage:
  bash email_migration.sh --dry-run
  bash email_migration.sh --dry-run --end 2025-06-30
  bash email_migration.sh --start 2025-01-01 --end 2025-06-30

Options:
  --dry-run           Run every read-only validation available before migration,
                      write a report, and STOP automatically before Gate A.
  --start YYYY-MM-DD  Override previous validated cutoff. Default comes from state
                      file, initially 2025-01-01.
  --end YYYY-MM-DD    Inclusive end of the six-month tranche. Default 2025-06-30.
  -h, --help          Show this help.

The first planned cycle is:
  2025-01-01 through 2025-06-30 inclusive.

This controller DOES NOT move mail by itself. In full mode it pauses at the
human gates and instructs the user when to use Apple Mail.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --start) START_CUTOFF="$2"; shift 2 ;;
    --end) END_INCLUSIVE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

REPORT_DIR="${HOME}/Desktop/Email-Migration-Reports"
STATE_DIR="${HOME}/Documents/Email-Migration"
STATE_FILE="${STATE_DIR}/state.txt"
mkdir -p "$REPORT_DIR" "$STATE_DIR"

if [ -z "$START_CUTOFF" ]; then
  if [ -f "$STATE_FILE" ]; then
    START_CUTOFF="$(awk -F= '/^last_successful_cutoff=/{print $2}' "$STATE_FILE" | tail -1)"
  fi
  START_CUTOFF="${START_CUTOFF:-2025-01-01}"
fi

END_EXCLUSIVE="$(python3 - "$END_INCLUSIVE" <<'PY'
from datetime import date, timedelta
import sys
print((date.fromisoformat(sys.argv[1]) + timedelta(days=1)).isoformat())
PY
)"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT="${REPORT_DIR}/migration-${START_CUTOFF}_to_${END_INCLUSIVE}-${STAMP}.txt"
JSON_REPORT="${REPORT%.txt}.json"
MAILROOT="${HOME}/Library/Mail"

log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
section() { log ""; log "======================================================================"; log "$*"; log "======================================================================"; }
stop_hold() { log "*** HOLD: $*"; log "No destructive step should follow a failed gate."; exit 3; }
pause_gate() {
  log ""
  read -r -p "$1 [type YES to continue]: " answer
  if [ "$answer" != "YES" ]; then
    log "STOPPED by human validation gate."
    exit 2
  fi
  log "Gate approved."
}

section "EMAIL MIGRATION CONTROLLER"
log "Mode      : $MODE"
log "Timestamp : $(date)"
log "Host      : $(hostname)"
log "User      : $(id -un)"
log "Window    : $START_CUTOFF <= date < $END_EXCLUSIVE"
log "Human form: $START_CUTOFF through $END_INCLUSIVE inclusive"
log "Report    : $REPORT"
log "Scope     : iCloud + Catolica/M365 -> Gmail historical archives"
log "Excluded  : Hotmail and Carrot (closed historical accounts)"

if ! command -v python3 >/dev/null 2>&1; then
  stop_hold "python3 is required by the controller."
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
  stop_hold "sqlite3 is required by the controller."
fi

section "1. PRE-FLIGHT"
log "macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
log "Free disk space:"
df -h "$HOME" | tee -a "$REPORT"
log ""
log "Apple Mail process:"
pgrep -fl '/Mail.app/|Mail$' 2>/dev/null | tee -a "$REPORT" || log "Apple Mail process not detected."
log ""
log "NOTE: Apple Mail Activity must be manually confirmed IDLE before a real run."

section "2. ACTIVE ENVELOPE INDEX DISCOVERY"
INDEX="$(python3 - "$MAILROOT" <<'PY'
from pathlib import Path
import sys
base=Path(sys.argv[1])
c=[]
for p in base.glob('V*/MailData/Envelope Index'):
    try: v=int(p.parents[1].name[1:])
    except: v=-1
    c.append((v,p))
if not c:
    sys.exit(1)
c.sort(reverse=True,key=lambda x:x[0])
print(c[0][1])
PY
)" || stop_hold "No Envelope Index found under ~/Library/Mail/V*/MailData."
log "Active Envelope Index: $INDEX"
ls -lh "$INDEX" | tee -a "$REPORT"

section "3. SQLITE HEALTH BASELINE"
INTEGRITY="$(sqlite3 "$INDEX" 'PRAGMA integrity_check;' 2>&1)"
log "integrity_check: $INTEGRITY"
[ "$INTEGRITY" = "ok" ] || stop_hold "Envelope Index integrity_check did not return ok."
FK="$(sqlite3 "$INDEX" 'PRAGMA foreign_key_check;' 2>&1)"
if [ -n "$FK" ]; then
  log "$FK"
  stop_hold "foreign_key_check returned rows."
else
  log "foreign_key_check: clean"
fi

section "4. DYNAMIC MAILBOX DISCOVERY + SOURCE/DESTINATION BASELINE"
BASELINE_JSON="$(python3 - "$INDEX" "$START_CUTOFF" "$END_EXCLUSIVE" <<'PY'
import sqlite3, sys, json
from urllib.parse import urlparse, unquote
idx,start,end=sys.argv[1:]
con=sqlite3.connect(f'file:{idx}?mode=ro',uri=True)
con.row_factory=sqlite3.Row
rows=con.execute('''
SELECT mb.ROWID rowid, mb.url url, COUNT(m.ROWID) total,
 CASE WHEN COUNT(m.ROWID)=0 THEN NULL ELSE datetime(MIN(m.date_sent),'unixepoch','localtime') END oldest,
 CASE WHEN COUNT(m.ROWID)=0 THEN NULL ELSE datetime(MAX(m.date_sent),'unixepoch','localtime') END newest
FROM mailboxes mb LEFT JOIN messages m ON m.mailbox=mb.ROWID
GROUP BY mb.ROWID,mb.url ORDER BY mb.url
''').fetchall()
boxes=[]
for r in rows:
    p=urlparse(r['url']); path=unquote(p.path.lstrip('/'))
    boxes.append(dict(rowid=r['rowid'],url=r['url'],scheme=p.scheme,account=p.netloc,path=path,total=r['total'],oldest=r['oldest'],newest=r['newest']))
from collections import defaultdict
g=defaultdict(list)
for b in boxes:g[(b['scheme'],b['account'])].append(b)
# Gmail = IMAP account containing both recurring archive folders
gmail=[]
for k,v in g.items():
    paths={b['path'] for b in v}
    if k[0]=='imap' and {'Archive - iCloud','Archive - Catolica'}<=paths:gmail.append((k,v))
if len(gmail)!=1: raise SystemExit(f'Cannot uniquely discover Gmail archive account; candidates={len(gmail)}')
gk,gb=gmail[0]
# M365 = EWS account with Inbox + Sent Items
ews=[]
for k,v in g.items():
    paths={b['path'] for b in v}
    if k[0]=='ews' and {'Inbox','Sent Items'}<=paths: ews.append((k,v))
if len(ews)!=1: raise SystemExit(f'Cannot uniquely discover M365/EWS account; candidates={len(ews)}')
_,mb=ews[0]
# iCloud = non-Gmail IMAP account with INBOX + Sent Messages
ics=[]
for k,v in g.items():
    paths={b['path'] for b in v}
    if k[0]=='imap' and k!=gk and {'INBOX','Sent Messages'}<=paths: ics.append((k,v))
if len(ics)!=1: raise SystemExit(f'Cannot uniquely discover iCloud account; candidates={len(ics)}')
_,ib=ics[0]
find=lambda arr,path: next(b for b in arr if b['path']==path)
roles={
 'icloud_inbox':find(ib,'INBOX'), 'icloud_sent':find(ib,'Sent Messages'),
 'm365_inbox':find(mb,'Inbox'), 'm365_sent':find(mb,'Sent Items'),
 'archive_icloud':find(gb,'Archive - iCloud'), 'archive_catolica':find(gb,'Archive - Catolica')}
def wc(b):
 r=con.execute('''SELECT COUNT(*) n,
 CASE WHEN COUNT(*)=0 THEN NULL ELSE datetime(MIN(date_sent),'unixepoch','localtime') END oldest,
 CASE WHEN COUNT(*)=0 THEN NULL ELSE datetime(MAX(date_sent),'unixepoch','localtime') END newest
 FROM messages WHERE mailbox=? AND date_sent>=strftime('%s',?) AND date_sent<strftime('%s',?)''',(b['rowid'],start,end)).fetchone()
 return dict(count=r['n'],oldest=r['oldest'],newest=r['newest'])
out={'roles':roles,'window':{k:wc(roles[k]) for k in ['icloud_inbox','icloud_sent','m365_inbox','m365_sent']}}
print(json.dumps(out))
PY
)" || stop_hold "Dynamic mailbox discovery failed."

printf '%s' "$BASELINE_JSON" > "${REPORT_DIR}/baseline-${STAMP}.json"
python3 - "$BASELINE_JSON" <<'PY' | tee -a "$REPORT"
import json,sys
d=json.loads(sys.argv[1])
print('Discovered mailboxes:')
for k,b in d['roles'].items(): print(f"  {k:<18} ROWID {b['rowid']:<5} path={b['path']:<22} total={b['total']}")
print('\nSource population in migration window:')
for k,w in d['window'].items(): print(f"  {k:<18} {w['count']:>6}  oldest={w['oldest'] or '-'}  newest={w['newest'] or '-'}")
i=d['window']['icloud_inbox']['count']+d['window']['icloud_sent']['count']
m=d['window']['m365_inbox']['count']+d['window']['m365_sent']['count']
print(f"  {'iCloud TOTAL':<18} {i:>6}")
print(f"  {'M365 TOTAL':<18} {m:>6}")
print('\nLocal Gmail archive baseline:')
print('  Archive - iCloud  :',d['roles']['archive_icloud']['total'])
print('  Archive - Catolica:',d['roles']['archive_catolica']['total'])
PY

section "5. LOCAL ACTION-QUEUE DIAGNOSTIC"
python3 - "$INDEX" <<'PY' | tee -a "$REPORT"
import sqlite3,sys
con=sqlite3.connect(f'file:{sys.argv[1]}?mode=ro',uri=True)
tables={r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
for name in ('local_message_actions','action_messages'):
    if name in tables:
        try: print(f'{name}: {con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]}')
        except Exception as e: print(f'{name}: present but count failed: {e}')
    else: print(f'{name}: not present in this Mail schema')
PY
log "A non-zero queue is diagnostic context, not automatically an error. Confirm Mail Activity manually."

section "6. SPOTLIGHT BASELINE"
mdutil -s / 2>&1 | tee -a "$REPORT"
log "Raw .emlx Spotlight counts are NOT used as a corpus-completeness test."

section "7. READ-ONLY DUPLICATE BASELINE — RECURRING ARCHIVES ONLY"
python3 - "$INDEX" "$BASELINE_JSON" <<'PY' | tee -a "$REPORT"
import sqlite3,json,sys
con=sqlite3.connect(f'file:{sys.argv[1]}?mode=ro',uri=True)
d=json.loads(sys.argv[2])
for key in ('archive_icloud','archive_catolica'):
    b=d['roles'][key]; rid=b['rowid']
    r=con.execute('''WITH x AS (
      SELECT global_message_id,COUNT(*) copies FROM messages
      WHERE mailbox=? AND global_message_id IS NOT NULL AND global_message_id!=''
      GROUP BY global_message_id HAVING COUNT(*)>1)
      SELECT COUNT(*) groups,COALESCE(SUM(copies-1),0) excess FROM x''',(rid,)).fetchone()
    print(f"{b['path']}: duplicate Message-ID groups={r[0]}, excess copies={r[1]}")
PY
log "Duplicate findings are audit evidence only. Tiny stable residues are not auto-cleaned."

section "8. GATE 1 — PRE-MIGRATION READINESS"
log "LOCAL checks completed:"
log "  - Envelope Index discovered dynamically"
log "  - integrity_check PASS"
log "  - foreign_key_check clean"
log "  - iCloud and M365 mailbox roles discovered dynamically"
log "  - exact source-window populations quantified"
log "  - local Gmail archive baseline captured"
log "  - action-queue diagnostic captured"
log "  - Spotlight status captured"
log "  - duplicate baseline captured"
log ""
log "Still required before a REAL migration:"
log "  1. Confirm Apple Mail Activity is idle."
log "  2. Independently confirm Gmail SERVER label counts for Archive - iCloud and Archive - Catolica."
log "  3. Compare those server counts with the local counts above."
log "  4. Human review of source populations and date window."

if [ "$MODE" = "dry-run" ]; then
  section "DRY RUN COMPLETE — AUTOMATIC STOP"
  log "No Gate A prompt was issued. No mail operation was requested."
  log "No mail was copied, moved, deleted, rebuilt or reindexed."
  log "Migration state was NOT advanced."
  log "Report saved: $REPORT"
  exit 0
fi

pause_gate "Gate 1 ready. Have you independently validated Gmail server counts and approved the source window?"

section "9. HUMAN GATE A — APPLE MAIL COPY"
log "Use Apple Mail to COPY the approved source tranche to the corresponding Gmail archive."
log "  iCloud -> Gmail / Archive - iCloud"
log "  Catolica/M365 -> Gmail / Archive - Catolica"
log "Use controlled/date-bounded batches."
log "Do NOT delete source mail yet."
pause_gate "Have the approved COPY batches finished and has Mail Activity settled?"

section "10. POST-COPY AUTOMATED RECONCILIATION"
POST_JSON="$(python3 - "$INDEX" "$START_CUTOFF" "$END_EXCLUSIVE" "$BASELINE_JSON" <<'PY'
import sqlite3,sys,json
idx,start,end,base=sys.argv[1:]
d=json.loads(base); con=sqlite3.connect(f'file:{idx}?mode=ro',uri=True)
con.row_factory=sqlite3.Row
def account(src1,src2,dst):
 r=con.execute('''SELECT COUNT(*) total,
 SUM(EXISTS(SELECT 1 FROM messages g WHERE g.mailbox=? AND g.global_message_id=s.global_message_id)) accounted,
 SUM(NOT EXISTS(SELECT 1 FROM messages g WHERE g.mailbox=? AND g.global_message_id=s.global_message_id)) missing
 FROM messages s WHERE s.mailbox IN (?,?) AND s.date_sent>=strftime('%s',?) AND s.date_sent<strftime('%s',?)''',(dst,dst,src1,src2,start,end)).fetchone()
 return dict(total=r['total'] or 0,accounted=r['accounted'] or 0,missing=r['missing'] or 0)
r=d['roles']
out={'icloud':account(r['icloud_inbox']['rowid'],r['icloud_sent']['rowid'],r['archive_icloud']['rowid']),
     'm365':account(r['m365_inbox']['rowid'],r['m365_sent']['rowid'],r['archive_catolica']['rowid'])}
print(json.dumps(out))
PY
)"
python3 - "$POST_JSON" <<'PY' | tee -a "$REPORT"
import json,sys
d=json.loads(sys.argv[1])
for k,v in d.items(): print(f"{k}: source_total={v['total']} accounted={v['accounted']} not_accounted={v['missing']}")
PY
MISSING="$(python3 - "$POST_JSON" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); print(d['icloud']['missing']+d['m365']['missing'])
PY
)"
if [ "$MISSING" -ne 0 ]; then
  stop_hold "$MISSING source messages are not accounted for in Gmail by global_message_id. Investigate exceptions before deletion."
fi
pause_gate "Gate 2 COPY reconciliation passes locally. Approve removal of the validated source tranche?"

section "11. HUMAN SOURCE CLEANUP"
log "Delete/remove ONLY the already reconciled source tranche in the live iCloud and M365 accounts."
log "Do NOT empty Bin/Deleted Items yet. Let synchronization finish."
pause_gate "Has source deletion synchronized and Mail Activity settled?"

section "12. POST-DELETION RECONCILIATION"
python3 - "$INDEX" "$START_CUTOFF" "$END_EXCLUSIVE" "$BASELINE_JSON" <<'PY' | tee -a "$REPORT"
import sqlite3,json,sys
idx,start,end,base=sys.argv[1:]
d=json.loads(base); con=sqlite3.connect(f'file:{idx}?mode=ro',uri=True); r=d['roles']
for k in ('icloud_inbox','icloud_sent','m365_inbox','m365_sent'):
 n=con.execute("SELECT COUNT(*) FROM messages WHERE mailbox=? AND date_sent>=strftime('%s',?) AND date_sent<strftime('%s',?)",(r[k]['rowid'],start,end)).fetchone()[0]
 print(f'{k}: remaining_in_migrated_window={n}')
PY
pause_gate "Gate 3 source cleanup is correct. Approve permanent emptying of the relevant source Bin/Deleted Items?"

section "13. FINAL SERVER CLEANUP"
log "Empty the relevant iCloud/M365 Bin/Deleted Items only now."
log "Let synchronization complete. Quit/reopen Mail; for the six-month final checkpoint, restart the Mac before final validation."
pause_gate "Has the restart/final sync checkpoint completed?"

section "14. FINAL LOCAL INTEGRITY + DUPLICATE CHECK"
INTEGRITY2="$(sqlite3 "$INDEX" 'PRAGMA integrity_check;' 2>&1)"
log "integrity_check: $INTEGRITY2"
[ "$INTEGRITY2" = "ok" ] || stop_hold "Final integrity_check failed."
FK2="$(sqlite3 "$INDEX" 'PRAGMA foreign_key_check;' 2>&1)"
[ -z "$FK2" ] || stop_hold "Final foreign_key_check returned rows."
log "foreign_key_check: clean"
log "Re-run this controller in --dry-run mode after restart if current ROWIDs changed; mailbox discovery is intentionally dynamic."

section "15. HUMAN GATE 4 — GMAIL SERVER <-> APPLE MAIL"
log "Independently query Gmail server label counts for Archive - iCloud and Archive - Catolica."
log "Compare EXACTLY with current local Envelope Index counts."
pause_gate "Do Gmail server and Apple Mail archive counts match exactly?"

section "16. SEARCH INTEGRITY"
log "For BOTH updated archives:"
log "  - test one known newly migrated message by distinctive SUBJECT text"
log "  - open it and test one distinctive BODY-only phrase"
log "  - confirm the expected historical message is returned"
log "Do not rebuild Envelope Index or Spotlight unless a controlled search actually fails."
pause_gate "Do subject and body-only searches pass in both updated archives?"

section "17. CLOSE / ADVANCE STATE"
log "All automated and human validation gates passed."
NEXT_CUTOFF="$END_EXCLUSIVE"
printf 'last_successful_cutoff=%s\n' "$NEXT_CUTOFF" > "$STATE_FILE"
log "State advanced to next start cutoff: $NEXT_CUTOFF"
log "State file: $STATE_FILE"
log "Final report: $REPORT"
log "Cycle CLOSED."
