# Creates a new tmux session with the specified name and window/pane configuration.
# Usage: create_tmux_session [-k] [-a] <session_name> [window1 window2 ...] -- [pane_count1 pane_count2 ...]
#   -k            Kill existing session if it exists
#   -a            Attach to the session after creation
#   session_name  Name for the new tmux session (default: td_dev)
#   window_names  Optional list of window names (default:  Build Test Support)
#   --            Separator before pane counts
#   pane_counts   Optional list of pane counts for each window (default: 1 for each)
# Examples:
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k test
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k test A B C D
#   source ${PRJ_PATH}/.vscode/scripts/commands.sh; create_tmux_session -k -a test A B C D -- 1 2 3 4
create_tmux_session() {
    local kill_existing=0
    local attach=0
    # Parse options
    while [[ "$1" == -* ]]; do
        case "$1" in
            -k) kill_existing=1 ;;
            -a) attach=1 ;;
            *) echo "Unknown option: $1"; return 1 ;;
        esac
        shift
    done

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
    # Fill missing pane counts with 1
    for ((i=${#pane_counts[@]}; i<${#window_names[@]}; i++)); do
        pane_counts+=(1)
    done

    # Kill or check for existing session
    if tmux has-session -t "$session_name" 2>/dev/null; then
        if (( kill_existing )); then
            tmux kill-session -t "$session_name"
        else
            echo "Session '$session_name' already exists. Use -k to kill it first."
            return 1
        fi
    fi

    # # Output the session and window configuration
    # echo "Creating tmux session '$session_name' with windows:"
    # for ((i=0; i<${#window_names[@]}; i++)); do
    #     echo "  Window: ${window_names[$i]} with ${pane_counts[$i]} panes"
    # done

    # Create each window and its panes
    for ((i=0; i<${#window_names[@]}; i++)); do
        local win_name="${window_names[$i]}"
        local num_panes="${pane_counts[$i]}"
        if (( i == 0 )); then
            tmux new-session -d -s "$session_name" -n "$win_name"
        else
            tmux new-window -t "$session_name:" -n "$win_name"
        fi

        # # Output log info
        # echo "  Creating window '$win_name' with $num_panes panes"

        # Create panes in the window
        for ((p=1; p<num_panes; p++)); do
            tmux split-window -t "${session_name}:$win_name"
        done
        # Arrange panes in tiled layout if more than one pane
        if (( num_panes > 1 )); then
            tmux select-layout -t "${session_name}:$win_name" tiled
        fi
    done

    # Attach to the session if -a is specified
    if (( attach )); then
        tmux attach-session -t "$session_name"
    fi
}

# Run a command in a tmux session, window, and pane.
# Usage: run_command_in_tmux [-s session] [-w window] [-p pane] [-a] [-y] [-l] -- <command>
#   -s session   : tmux session name (required)
#   -w window    : window index or name (default: 0)
#   -p pane      : pane index (default: 0)
#   -a           : run in all panes of the window
#   -y           : run synchronously (wait for command to finish)
#   -l           : use tmux send-keys -l (literal mode)
#   --           : command to run
# Examples:
#   run_command_in_tmux -s td_dev -w Build -- "\
#       echo 'Running build commands...'; \
#       cd /root/workspace/TDinternal/ && \
#       rm -rf debug && \
#       mkdir debug && \
#       cd debug && \
#       cmake .. && \
#       make -j4 && \
#       echo 'Build completed.'"
run_command_in_tmux() {
    local session="" window="0" pane="0" all_panes=0 sync=0 literal=0
    local OPTIND opt
    while getopts "s:w:p:ayl" opt; do
        case "$opt" in
            s) session="$OPTARG" ;;
            w) window="$OPTARG" ;;
            p) pane="$OPTARG" ;;
            a) all_panes=1 ;;
            y) sync=1 ;;
            l) literal=1 ;;
            *) echo "Invalid option: -$OPTARG" >&2; return 1 ;;
        esac
    done

    # Output the options and remaining arguments
    shift $((OPTIND-2))
    
    # Check for -- separator
    if [[ "$1" != "--" ]]; then
        echo "Usage: run_command_in_tmux [-s session] [-w window] [-p pane] [-a] [-y] [-l] -- <command>"
        echo "Error: Missing '--' separator before command" >&2
        return 1
    fi
    shift  # Remove the -- separator
    
    local cmd="$*"
    
    if [[ -z "$session" || -z "$cmd" ]]; then
        echo "Error: Session and command are required." >&2
        return 1
    fi

    # # Output the parsed options
    # echo "Running command in tmux session: '$session', window '$window', pane '$pane': $cmd"

    # Create session if missing
    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "Error: Session '$session' does not exist." >&2
        return 1
    fi

    # Check if window exists (by index or name)
    local window_exists=0
    if tmux list-windows -t "$session" | grep -qE "^[0-9]+: $window(-|*| |$)"; then
        window_exists=1
    elif tmux list-windows -t "$session" | grep -qE "^${window}:"; then
        window_exists=1
    fi

    if (( !window_exists )); then
        echo "Error: Window '$window' does not exist in session '$session'." >&2
        return 1
    fi

    # Check if pane exists
    local pane_exists=0
    if tmux list-panes -t "$session:$window" -F '#P' | grep -q "^${pane}$"; then
        pane_exists=1
    fi

    if (( !pane_exists )); then
        echo "Error: Pane '$pane' does not exist in window '$window'." >&2
        return 1
    fi

    # Run command
    if (( all_panes )); then
        local panes
        panes=$(tmux list-panes -t "$session:$window" -F '#P')
        for p in $panes; do
            if (( literal )); then
                tmux send-keys -t "$session:$window.$p" -l "$cmd" C-m
            else
                tmux send-keys -t "$session:$window.$p" "$cmd" C-m
            fi
        done
    else
        # echo "Running in pane $pane: $cmd"
        if (( sync )); then
            cmd="$cmd tmux wait-for -S ${session}_${window}_${pane}_done"
        fi
        echo $cmd
        if (( literal )); then
            tmux send-keys -t "$session:$window.$pane" -l "$cmd" C-m
        else
            tmux send-keys -t "$session:$window.$pane" "$cmd" C-m
        fi

        # Wait for command to finish if sync is set
        if (( sync )); then
            tmux wait-for ${session}_${window}_${pane}_done
        fi
    fi
}

# TODO: fix here
# run_command_in_tmux -s td_dev -w Test -y -- "\
# sleep 5; \
# "
    