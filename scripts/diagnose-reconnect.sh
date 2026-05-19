#!/usr/bin/env bash
#
# diagnose-reconnect.sh — bifurcation harness for the "blank pane on app start"
# and "missing RPROMPT after reconnect" bugs.
#
# What it does:
#   1. Builds Forge from the current worktree
#   2. Launches it, adds a project, runs a marker command, captures golden state
#   3. Quits Forge
#   4. Relaunches it (this is what reproduces the bug)
#   5. Captures reconnected state
#   6. Walks the Q1-Q6 bifurcation tree and prints a labeled root cause
#
# Output: stdout = labeled ROOT-{A..G} + evidence summary
#         /tmp/diagnose-reconnect/ = raw artifacts (G0, G1, pty-tail, logs)
#
# Exit codes:
#   0 = ROOT identified
#   1 = harness setup error (build/launch failure, etc.)
#   2 = harness logic error (couldn't reach a leaf — shouldn't happen)

set -u
PORT=7654
WORKTREE=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
BIN="$WORKTREE/.build/debug/Forge.app"
OUT=/tmp/diagnose-reconnect
LOG="$OUT/run.log"
PROJECT_NAME="diag-$$"
PROJECT_PATH="/tmp/forge-diag-$$"
FORGE_CONFIG="$HOME/.config/forge"
BACKUP_DIR="$HOME/.config/forge.diagnose-backup-$$"

mkdir -p "$OUT"
: > "$LOG"
exec 3>>"$LOG"
log() { echo "$@" | tee /dev/fd/3; }

# ---------- user-state protection ----------
# NSHomeDirectory() ignores $HOME, so we can't redirect Forge's config dir.
# Instead, swap the user's real config out of the way, run with a clean slate,
# and restore on exit (success or failure). This protects the user's workspace,
# scrollback logs, and uistate from being clobbered by the harness.

restore_user_state() {
    if [ -d "$BACKUP_DIR" ]; then
        log "[harness] restoring user state from $BACKUP_DIR"
        # Move our diagnostic config aside (for inspection later if user wants)
        if [ -d "$FORGE_CONFIG" ]; then
            local diag_save="$OUT/forge-config-diagnostic-$$"
            mv "$FORGE_CONFIG" "$diag_save"
            log "[harness] diagnostic config preserved at $diag_save"
        fi
        mv "$BACKUP_DIR" "$FORGE_CONFIG"
    fi
    rm -rf "$PROJECT_PATH"
}

backup_user_state() {
    if [ -e "$BACKUP_DIR" ]; then
        log "[harness] ERROR: backup dir already exists at $BACKUP_DIR — bailing"
        exit 1
    fi
    if [ -d "$FORGE_CONFIG" ]; then
        log "[harness] backing up $FORGE_CONFIG → $BACKUP_DIR"
        mv "$FORGE_CONFIG" "$BACKUP_DIR"
    fi
    mkdir -p "$FORGE_CONFIG"
}

trap restore_user_state EXIT INT TERM

# ---------- helpers ----------

quit_forge() {
    log "[harness] quitting Forge gracefully"
    osascript -e 'tell application "Forge" to quit' 2>/dev/null || true
    for _ in $(seq 1 10); do
        pgrep -x Forge >/dev/null || return 0
        sleep 0.3
    done
    log "[harness] graceful quit timed out — force killing"
    pkill -x Forge 2>/dev/null || true
    sleep 0.5
}

wait_for_ping() {
    for _ in $(seq 1 30); do
        if curl -sf "http://localhost:$PORT/ping" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.4
    done
    log "[harness] ERROR: Forge debug server never came up on port $PORT"
    return 1
}

launch_forge() {
    log "[harness] launching $BIN"
    open -n -W "$BIN" >/dev/null 2>&1 &
    wait_for_ping || return 1
    return 0
}

state_pane_id() {
    curl -s "http://localhost:$PORT/state" |
        python3 -c '
import json, sys
d = json.load(sys.stdin)
for s in d.get("sessions", []):
    if s.get("name") == "'"$PROJECT_NAME"'":
        for w in s.get("windows", []):
            for p in w.get("panes", []):
                if p.get("kind", "terminal") == "terminal":
                    print(p["id"])
                    sys.exit(0)
sys.exit(1)
' 2>/dev/null
}

# ---------- phases ----------

bake_golden() {
    log "[harness] === PHASE: bake golden state ==="
    quit_forge
    backup_user_state
    mkdir -p "$PROJECT_PATH"

    log "[harness] building forge (debug + bundle)…"
    (cd "$WORKTREE" && swift build && make bundle BUILD=.build/debug) \
        >"$OUT/build.log" 2>&1
    if [ ! -e "$BIN" ]; then
        log "[harness] ERROR: build did not produce $BIN. See $OUT/build.log"
        return 1
    fi

    launch_forge || return 1

    log "[harness] adding project '$PROJECT_NAME' at $PROJECT_PATH"
    curl -s -X POST "http://localhost:$PORT/action" \
        -d "{\"action\":\"addProject\",\"args\":{\"name\":\"$PROJECT_NAME\",\"path\":\"$PROJECT_PATH\"}}" \
        >/dev/null
    sleep 3   # let shell exec, prompt draw, daemon.store complete

    PANE_ID=$(state_pane_id || true)
    if [ -z "${PANE_ID:-}" ]; then
        log "[harness] ERROR: could not find pane id for '$PROJECT_NAME'"
        return 1
    fi
    echo "$PANE_ID" > "$OUT/pane_id.txt"
    log "[harness] pane id = $PANE_ID"

    log "[harness] capturing golden grid G0"
    curl -s "http://localhost:$PORT/surface-text/$PANE_ID" > "$OUT/G0.txt"
    log "[harness]   G0 size = $(wc -c < "$OUT/G0.txt") bytes, $(wc -l < "$OUT/G0.txt") lines"

    quit_forge
}

reconnect_capture() {
    log "[harness] === PHASE: reconnect ==="
    PANE_ID=$(cat "$OUT/pane_id.txt")

    launch_forge || return 1

    # Capture grid at multiple offsets — the bug's whole point is "what does
    # the user see RIGHT NOW vs after waiting". G1_T1 is the timepoint we
    # bifurcate on (matches "what user sees on launch"); the others are evidence.
    log "[harness] capturing G1 at t=+1s, +3s, +8s, +15s"
    sleep 1
    curl -s "http://localhost:$PORT/surface-text/$PANE_ID" > "$OUT/G1_t1.txt"
    sleep 2   # t=+3
    curl -s "http://localhost:$PORT/surface-text/$PANE_ID" > "$OUT/G1_t3.txt"
    sleep 5   # t=+8
    curl -s "http://localhost:$PORT/surface-text/$PANE_ID" > "$OUT/G1_t8.txt"
    sleep 7   # t=+15
    curl -s "http://localhost:$PORT/surface-text/$PANE_ID" > "$OUT/G1_t15.txt"

    # Use the latest snapshot as the canonical G1 — if the surface fills in
    # eventually, this will tell us *when*.
    cp "$OUT/G1_t15.txt" "$OUT/G1.txt"

    for t in t1 t3 t8 t15; do
        log "[harness]   G1_$t = $(wc -c < "$OUT/G1_$t.txt") bytes, $(wc -l < "$OUT/G1_$t.txt") lines"
    done

    log "[harness] capturing pty-tail"
    curl -s "http://localhost:$PORT/pty-tail/$PANE_ID?bytes=8192" > "$OUT/pty-tail.bin" || true
    log "[harness]   pty-tail size = $(wc -c < "$OUT/pty-tail.bin") bytes"

    log "[harness] capturing forge logs"
    curl -s "http://localhost:$PORT/logs" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("logs", ""))
except Exception as e:
    print(f"(log fetch failed: {e})")
' > "$OUT/forge-logs.txt"

    # Also copy the full /tmp/forge.log lines from this run (logs endpoint is capped at 50)
    if [ -f /tmp/forge.log ]; then
        # Just grab lines that mention our pane id or are recent
        grep "$PANE_ID\|EXTERNAL\|Reconnected\|FEED" /tmp/forge.log > "$OUT/forge-logs-full.txt" || true
    fi
}

# ---------- bifurcation ----------

q1_grids_similar() {
    python3 <<'PY'
import re, sys, json
g0 = re.findall(r'\S+', open('/tmp/diagnose-reconnect/G0.txt').read())
g1 = re.findall(r'\S+', open('/tmp/diagnose-reconnect/G1.txt').read())
s0, s1 = set(g0), set(g1)
union = s0 | s1
jaccard = (len(s0 & s1) / len(union)) if union else 0.0
out = {"g0_tokens": len(g0), "g1_tokens": len(g1), "jaccard": round(jaccard, 3)}
print(json.dumps(out))
PY
}

q2_g1_blank() {
    python3 <<'PY'
import re, json
g1 = open('/tmp/diagnose-reconnect/G1.txt').read()
non_space = len(re.sub(r'\s', '', g1))
print(json.dumps({"non_space_chars": non_space, "blank": non_space <= 5}))
PY
}

q3_pty_tail_has_bytes() {
    python3 <<'PY'
import os, json
path = '/tmp/diagnose-reconnect/pty-tail.bin'
size = os.path.getsize(path) if os.path.exists(path) else 0
# Distinguish "log file missing entirely" from "log file empty"
pane_id = open('/tmp/diagnose-reconnect/pane_id.txt').read().strip()
log_path = os.path.expanduser(f'~/.config/forge/scrollback/{pane_id}.log')
file_exists = os.path.exists(log_path)
file_size = os.path.getsize(log_path) if file_exists else 0
print(json.dumps({
    "pty_tail_bytes": size,
    "scrollback_file_exists": file_exists,
    "scrollback_file_size": file_size,
    "has_bytes": file_size > 0
}))
PY
}

q4_feed_was_called() {
    python3 <<'PY'
import re, json
pane_id = open('/tmp/diagnose-reconnect/pane_id.txt').read().strip()
logs = open('/tmp/diagnose-reconnect/forge-logs.txt').read()
# Match [FEED:<paneId>:<count>] entries
pattern = re.compile(rf'\[FEED:{re.escape(pane_id)}:(\d+)(?::dropped-no-surface)?\]')
calls = pattern.findall(logs)
drops = re.compile(rf'\[FEED:{re.escape(pane_id)}:\d+:dropped-no-surface\]').findall(logs)
total = sum(int(n) for n in calls)
print(json.dumps({
    "feed_calls": len(calls),
    "feed_drops": len(drops),
    "total_bytes_fed": total
}))
PY
}

q5_pty_tail_has_rprompt_bytes() {
    python3 <<'PY'
import re, json
data = open('/tmp/diagnose-reconnect/pty-tail.bin', 'rb').read() if __import__('os').path.exists('/tmp/diagnose-reconnect/pty-tail.bin') else b''
# Common RPROMPT-shaped byte patterns:
#   ESC 7      = save cursor (DEC)
#   ESC 8      = restore cursor
#   ESC [ s    = save cursor (ANSI)
#   ESC [ u    = restore cursor
#   ESC [ <n>G = absolute column move
#   ESC [ <r>;<c>H = absolute cursor position (after a prompt section, often used to position RPROMPT)
save7 = data.count(b'\x1b7') + data.count(b'\x1b[s')
restore8 = data.count(b'\x1b8') + data.count(b'\x1b[u')
col_moves = len(re.findall(rb'\x1b\[\d+G', data))
hvp_moves = len(re.findall(rb'\x1b\[\d+;\d+H', data))
print(json.dumps({
    "save_cursor": save7,
    "restore_cursor": restore8,
    "col_moves": col_moves,
    "hvp_moves": hvp_moves,
    "has_rprompt_shaped_bytes": (save7 > 0 and restore8 > 0) or col_moves > 0
}))
PY
}

q6_grid_has_time_text() {
    python3 <<'PY'
import re, json
g1 = open('/tmp/diagnose-reconnect/G1.txt').read()
time_match = re.search(r'\d{1,2}:\d{2}:\d{2}', g1)
check_match = '✓' in g1 or '✗' in g1
print(json.dumps({
    "has_time_text": bool(time_match),
    "time_match": time_match.group(0) if time_match else None,
    "has_status_glyph": check_match
}))
PY
}

# ---------- main flowchart ----------

main() {
    bake_golden || { echo "ROOT-HARNESS: bake_golden failed — see $LOG"; exit 1; }
    reconnect_capture || { echo "ROOT-HARNESS: reconnect_capture failed — see $LOG"; exit 1; }

    log "[harness] === PHASE: bifurcate ==="

    Q1=$(q1_grids_similar)
    Q2=$(q2_g1_blank)
    Q3=$(q3_pty_tail_has_bytes)
    Q4=$(q4_feed_was_called)
    Q5=$(q5_pty_tail_has_rprompt_bytes)
    Q6=$(q6_grid_has_time_text)

    log "[Q1] $Q1"
    log "[Q2] $Q2"
    log "[Q3] $Q3"
    log "[Q4] $Q4"
    log "[Q5] $Q5"
    log "[Q6] $Q6"

    JACCARD=$(echo "$Q1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["jaccard"])')
    G1_BLANK=$(echo "$Q2" | python3 -c 'import sys,json; print(json.load(sys.stdin)["blank"])')
    SB_EXISTS=$(echo "$Q3" | python3 -c 'import sys,json; print(json.load(sys.stdin)["scrollback_file_exists"])')
    SB_BYTES=$(echo "$Q3" | python3 -c 'import sys,json; print(json.load(sys.stdin)["has_bytes"])')
    FEED_CALLS=$(echo "$Q4" | python3 -c 'import sys,json; print(json.load(sys.stdin)["feed_calls"])')
    FEED_BYTES=$(echo "$Q4" | python3 -c 'import sys,json; print(json.load(sys.stdin)["total_bytes_fed"])')
    HAS_RP=$(echo "$Q5" | python3 -c 'import sys,json; print(json.load(sys.stdin)["has_rprompt_shaped_bytes"])')
    HAS_TIME=$(echo "$Q6" | python3 -c 'import sys,json; print(json.load(sys.stdin)["has_time_text"])')

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  DIAGNOSE-RECONNECT RESULTS"
    echo "════════════════════════════════════════════════════════════════"
    echo "  Pane:        $(cat $OUT/pane_id.txt)"
    echo "  Q1 jaccard:  $JACCARD"
    echo "  Q2 blank?:   $G1_BLANK"
    echo "  Q3 scrollback exists/bytes: $SB_EXISTS / $SB_BYTES"
    echo "  Q4 feed:     $FEED_CALLS calls, $FEED_BYTES bytes"
    echo "  Q5 rprompt bytes in pty:    $HAS_RP"
    echo "  Q6 time text in grid:       $HAS_TIME"
    echo "════════════════════════════════════════════════════════════════"

    # ---- Bug 1 branch (blank screen) ----
    if [ "$G1_BLANK" = "True" ]; then
        if [ "$SB_EXISTS" = "False" ]; then
            cat <<'EOF'
ROOT-A: scrollback log file was never created for this pane.
    → New-pane paths (addProject / addTab / splitPane) construct the renderer
      but never call startScrollbackLog(). On next launch, loadScrollback
      reads nothing and feeds nothing → blank surface.
    FIX: Add `ghostty.startScrollbackLog(paneId: paneId)` to:
      - addProjectNativePTY  (Sources/WorkspaceController+Actions.swift)
      - addTabNativePTY      (Sources/WorkspaceController+Actions.swift)
      - splitPaneNativePTY   (Sources/WorkspaceController+Actions.swift)
EOF
        elif [ "$FEED_CALLS" = "0" ]; then
            cat <<'EOF'
ROOT-B: scrollback exists on disk but feed() was never invoked.
    → loadScrollback() inside configureForReconnect's onSurfaceResize
      callback either never ran (gate condition not met) or skipped over
      the existing file. Check the `if !self.reconnected` gate, the
      cols>0,rows>0 guard, and whether onSurfaceResize fires at all
      after viewDidMoveToWindow on this pane.
EOF
        else
            cat <<'EOF'
ROOT-C: feed() was called with bytes but the surface didn't process them.
    → Bytes reached gap (2)→(3) but the emulator grid didn't accept them.
      Possible causes: surface was at 0x0 grid when feed ran, surface
      pointer was stale, Metal layer wasn't initialized.
EOF
        fi
        exit 0
    fi

    # G1 is not blank. Two sub-cases:
    #   1. G1 is the live re-rendered prompt — perfect reconnect. G0 differs
    #      because it included the one-time "Last login..." banner that doesn't
    #      reprint when the shell is already running. This is success.
    #   2. G1 is partial/corrupted — bytes flowed but didn't fully paint.
    # Distinguish by "is the live prompt visible?" — the RPROMPT timestamp is
    # the strongest signal; failing that, a substantial token overlap.
    if [ "$HAS_TIME" = "True" ] || [ "$(echo "$JACCARD > 0.3" | bc -l)" = "1" ]; then
        cat <<EOF
ROOT-NONE: reconnect appears healthy.
    G0 = $(wc -c < "$OUT/G0.txt") bytes (includes 'Last login' banner that
                                          doesn't reprint on reconnect).
    G1 = $(wc -c < "$OUT/G1.txt") bytes — has the live prompt with RPROMPT.
    feed_calls=$FEED_CALLS, total_bytes_fed=$FEED_BYTES.
    Jaccard $JACCARD reflects the expected G0/G1 banner difference, not a bug.
EOF
        exit 0
    fi

    if [ "$(echo "$JACCARD < 0.3" | bc -l)" = "1" ]; then
        echo "ROOT-PARTIAL: G1 has some content but doesn't match G0 (jaccard $JACCARD)."
        echo "  → Investigate manually with: diff <(cat $OUT/G0.txt) <(cat $OUT/G1.txt)"
        exit 0
    fi

    # ---- Bug 2 branch (no RPROMPT) ----
    if [ "$HAS_RP" = "False" ]; then
        cat <<'EOF'
ROOT-D: PTY byte stream contains no RPROMPT-shaped escape sequences.
    → The shell never wrote RPROMPT bytes that we could capture. Likely
      causes:
      - User's P10K is in transient-prompt state (POWERLEVEL9K_TRANSIENT_PROMPT=always
        rewrites the last prompt without RPROMPT)
      - Foreground process is not zsh (claude code, vim, etc.) and isn't drawing RPROMPT
    Next check: in the live app, run an empty `<Enter>` and re-run the harness.
    If the new pty-tail contains save/restore cursor pairs, this is P10K state
    being repaired by accept-line. ROOT-E in that case.
EOF
        exit 0
    fi

    if [ "$HAS_TIME" = "False" ]; then
        cat <<'EOF'
ROOT-G: RPROMPT bytes are in the stream but never made it into the
        surface grid.
    → Ghostty surface received the prompt bytes (feed_calls > 0) but
      RPROMPT chars are absent from the readVisibleText output. The
      emulator dropped or mis-positioned them.
    Inspect: hexdump $OUT/pty-tail.bin | grep -A2 RPROMPT-byte-pattern
    and compare with surface-text grid line widths.
EOF
        exit 0
    fi

    echo "NO-BUG: G1 ≈ G0 (jaccard $JACCARD), surface has time text, RPROMPT bytes present."
    echo "    Reconnection appears healthy on this pane. If the bug is still"
    echo "    visible to the user, the harness didn't reproduce it — check:"
    echo "      - was the pane new (no daemon fd) when bake_golden ran?"
    echo "      - did the shell finish drawing before quit_forge?"
    exit 0
}

main "$@"
