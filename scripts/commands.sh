# Creates a new tmux session with the specified name and window/pane configuration.
# Usage: create_tmux_session [-k] <session_name> [window1 window2 ...] -- [pane_count1 pane_count2 ...]
#   -k            Kill existing session if it exists
#   session_name  Name for the new tmux session (default: td_dev)
#   window_names  Optional list of window names (default: Build Test Support)
#   --            Separator before pane counts
#   pane_counts   Optional list of pane counts for each window (default: 1 for each)
# Examples:
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session 
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k test
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k test A B C D
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k test A B C D -- 1 2 3 4
create_tmux_session() {
    local kill_existing=0
    if [[ "$1" == "-k" ]]; then
        kill_existing=1
        shift
    fi

    local session_name="${1:-td_dev}"
    shift

    # Parse window names and pane counts
    local window_names=()
    local pane_counts=()
    local parsing_panes=0
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            parsing_panes=1
            shift
            continue
        fi
        if (( parsing_panes )); then
            pane_counts+=("$1")
        else
            window_names+=("$1")
        fi
        shift
    done
    if [[ ${#window_names[@]} -eq 0 ]]; then
        window_names=("Build" "Test" "Support")
    fi
    # Default pane count is 1 if not specified
    for ((i=${#pane_counts[@]}; i<${#window_names[@]}; i++)); do
        pane_counts+=(1)
    done

    # Check if session exists
    if tmux has-session -t "$session_name" 2>/dev/null; then
        if (( kill_existing )); then
            tmux kill-session -t "$session_name"
        else
            echo "Session '$session_name' already exists. Use -k to kill it first."
            return 1
        fi
    fi

    # Create session and windows with panes
    tmux new-session -d -s "$session_name" -n "${window_names[0]}"
    for ((i=0; i<${#window_names[@]}; i++)); do
        local win="${window_names[$i]}"
        local panes="${pane_counts[$i]}"
        if (( i > 0 )); then
            tmux new-window -t "${session_name}:" -n "$win"
        fi
        # Create panes in the window
        for ((p=1; p<panes; p++)); do
            tmux split-window -t "${session_name}:$i"
            tmux select-layout -t "${session_name}:$i" tiled
        done
    done

    # Attach to the session
    tmux attach-session -t "$session_name"
}
