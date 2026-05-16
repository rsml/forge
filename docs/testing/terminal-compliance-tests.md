# Terminal Compliance Test Plan

Exhaustive tests to verify Forge's native pane renderer behaves identically to a real Ghostty terminal.

## 1. Input Tests

### Printable Characters
```bash
# In each pane, type these and verify they appear:
echo "hello world"          # letters + space
echo "Hello World 123"      # mixed case + numbers
echo "!@#$%^&*()"           # symbols
echo "path/to/file.txt"     # slashes, dots
echo 'single quotes'        # single quotes
echo "double \"quotes\""    # double quotes with escapes
echo "semi;colon"           # semicolons (tmux special char)
echo "back\\slash"          # backslashes
echo "tilde ~ dollar $VAR"  # tilde, dollar
```

### Control Characters
```bash
# Test each in a running shell:
Ctrl+C    # interrupt (should kill current process, show ^C)
Ctrl+D    # EOF (should close shell if empty line)
Ctrl+Z    # suspend
Ctrl+L    # clear screen
Ctrl+A    # beginning of line (in zsh)
Ctrl+E    # end of line
Ctrl+W    # delete word backward
Ctrl+U    # delete to beginning of line
Ctrl+R    # reverse search
Ctrl+\    # SIGQUIT
```

### Special Keys
```bash
# Arrow keys: up/down for history, left/right for cursor movement
# Home/End: jump to beginning/end of line
# PageUp/PageDown: scroll in less/man
# Tab: autocomplete
# Backspace: delete char before cursor
# Delete (fn+backspace): delete char after cursor
# Escape: cancel in various contexts
# Return/Enter: execute command
```

### Multi-pane Input Routing
```bash
# With 2+ panes visible:
# 1. Click pane A, type "aaa" → should appear in pane A only
# 2. Click pane B, type "bbb" → should appear in pane B only
# 3. Click pane A, Ctrl+C → should interrupt pane A only
# 4. Click pane B, Ctrl+C → should interrupt pane B only
# Verify: no key leaks to wrong pane
```

## 2. Output Rendering Tests

### Basic Output
```bash
echo "plain text"
printf "\033[31mred\033[0m \033[32mgreen\033[0m \033[34mblue\033[0m"   # ANSI colors
printf "\033[1mbold\033[0m \033[4munderline\033[0m \033[7mreverse\033[0m"
ls --color                    # colored directory listing
```

### Full-width Terminal Content
```bash
# The right-side prompt/timestamp should be at the RIGHT EDGE of the pane:
# (powerlevel10k/oh-my-zsh puts status on the right)
echo "test" # observe prompt after — timestamp at right edge?

# Fill entire width:
printf '%0.s=' $(seq 1 $(tput cols))   # line of '=' filling full width
```

### Scrolling
```bash
seq 1 1000              # lots of output — scroll up works?
man ls                   # pager — scroll works? q to quit?
less /etc/hosts          # less — PageUp/PageDown work?
```

### Cursor Positioning
```bash
# Test cursor movement in editors:
nano /tmp/test.txt       # cursor moves correctly?
vi /tmp/test.txt         # modes work? insert, command, visual?
```

## 3. TUI Application Tests

### Basic TUIs
```bash
htop                     # fills pane? resize pane while running — redraws?
top                      # fills pane?
nano /tmp/test.txt       # fills pane? bottom status bar visible?
vi /tmp/test.txt         # fills pane? status line at bottom?
```

### Advanced TUIs
```bash
# Claude Code (Ink-based React terminal UI):
claude                   # Full UI visible? Input line at bottom?
                         # Resize pane while running — redraws cleanly?

# If available:
lazygit                  # complex TUI — panels render correctly?
```

### Alternate Screen Buffer
```bash
# Test programs that use the alternate screen:
less /etc/hosts          # enter alt screen — exit (q) restores original
vi /tmp/test.txt         # enter alt screen — :q restores original
man ls                   # enter alt screen — q restores original
# After exit: previous shell output should be restored (not garbled)
```

## 4. Resize Tests

### Single Pane Window Resize
```bash
# 1. Type a long command prompt
# 2. Drag app window edge to resize
# 3. Verify: prompt reflows correctly, no garbled text
# 4. curl localhost:7654/pane-sizes — mismatch: false
```

### Split Pane Divider Drag
```bash
# 1. Create horizontal split
# 2. Run `htop` in one pane
# 3. Drag the divider
# 4. Verify: htop redraws cleanly after release
# 5. curl localhost:7654/pane-sizes — all mismatch: false
```

### Resize with TUI Running
```bash
# 1. Run `claude` in a split pane
# 2. Resize the app window
# 3. Verify: Claude Code redraws, input line visible
# 4. Resize the split divider
# 5. Verify: Claude Code redraws, input line visible
```

## 5. Lifecycle Tests

### App Restart
```bash
# 1. Set up splits with specific proportions (e.g., 30/70)
# 2. Note divider position (screenshot)
# 3. Close app, reopen
# 4. Verify: divider at same position
# 5. Verify: all panes show content (not blank)
# 6. curl localhost:7654/pane-sizes — all mismatch: false
```

### Project Switch
```bash
# 1. Have 2 projects with different pane layouts
# 2. Switch between them
# 3. Verify: each project's panes render correctly
# 4. Verify: no blank screens on switch
```

### Split Creation/Removal
```bash
# 1. Start with single pane
# 2. Split horizontally — new pane shows prompt?
# 3. Split vertically — new pane shows prompt?
# 4. Close a split — remaining panes still show content?
# 5. Close all splits — single pane renders correctly?
```

## 6. Diagnostic Verification

After EVERY test above, run:
```bash
curl localhost:7654/pane-sizes | python3 -m json.tool
```

Check:
- [ ] `summary` says "ok"
- [ ] Every pane has `mismatch: false`
- [ ] `terminalCellSize` has integer or near-integer values
- [ ] `computedCellSize` is consistent across all panes (same font)

Also check logs:
```bash
tail -20 /tmp/forge.log | grep -E "Dropped|error|Cell size"
```

- [ ] No "Dropped command" lines
- [ ] Cell size logged with clean values from ghostty

## 7. Edge Cases

- [ ] Very narrow pane (drag divider to ~10 cols) — content wraps, no crash
- [ ] Very short pane (drag divider to ~3 rows) — prompt visible, no crash
- [ ] Window maximized → restored — panes resize correctly
- [ ] Window moved to different display (different scale factor?) — still renders
- [ ] Rapid divider dragging back and forth — no ghost lines, no crash
- [ ] Create 4+ panes (complex nested splits) — all render correctly
