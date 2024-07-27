#!/bin/bash
#shellcheck disable=SC2002,SC1091,SC2034
# TODO: Finish CSV validation and add IP TCP connection check, port validation, key file existence and permissions validation.
# TODO: Add execution of the cryptsetup-unlock script on the remote host.
# NOTE: Editing the inventory does not need a restart, the script will pick up the changes in the next iteration.
# NOTE: Editing the .env file will not take effect until the script is restarted.
_SCRIPT_VERSION="0.2.0"
_SCRIPT_NAME="xxHecate"

#####################################
#### Configuration
#####################################
XXHECATE_INVENTORY="${XXHECATE_INVENTORY:-inventory.csv}"
XXHECATE_LOG_FILE="${XXHECATE_LOG_FILE:-xxHecate.log}"
XXHECATE_SLEEP_DURATION="${XXHECATE_SLEEP_DURATION:-60}"
# TODO: Remove this after testing is done.

#####################################
#### Constants
#####################################
XXHECATE_DEBUG_FLAG="${_SCRIPT_NAME}_DEBUG_MODE"
XXHECATE_DEBUG_FLAG=$(echo "$XXHECATE_DEBUG_FLAG" | tr '[:lower:]' '[:upper:]')
XXHECATE_DEBUG_MODE=$(if [[ -f $XXHECATE_DEBUG_FLAG ]]; then echo 1; else echo 0; fi)

#####################################
#### Helpers
#####################################
fblack='\e[0;30m'        # Black
fred='\e[0;31m'          # Red
fgreen='\e[0;32m'        # Green
fyellow='\e[0;33m'       # Yellow
fblue='\e[0;34m'         # Blue
fpurple='\e[0;35m'       # Purple
fcyan='\e[0;36m'         # Cyan
fwhite='\e[0;37m'        # White
bblack='\e[1;30m'        # Black
bred='\e[1;31m'          # Red
bgreen='\e[1;32m'        # Green
byellow='\e[1;33m'       # Yellow
bblue='\e[1;34m'         # Blue
bpurple='\e[1;35m'       # Purple
bcyan='\e[1;36m'         # Cyan
bwhite='\e[1;37m'        # White
nc="\e[m"                # Color Reset
nl="\n"                  # New Line

function log() {
    local _message="$1"
    local _level="$2" # Expect 'INFO', 'WARN', 'ERROR', 'DEBUG'
    local _timestamp
    local log_file="$XXHECATE_LOG_FILE"
    _timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # Ensure log file exists
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
    fi

    case $(echo "$_level" | tr '[:upper:]' '[:lower:]') in
    "info" | "information")
        echo -ne "${bwhite}[INFO][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -s "$log_file" ]; then echo "$(date +'%Y-%m-%d %H:%M:%S') - [INFO] $_message" >> "$log_file"; fi
        ;;
    "warn" | "warning")
        echo -ne "${byellow}[WARN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -s "$log_file" ]; then echo "$(date +'%Y-%m-%d %H:%M:%S') - [WARN] $_message" >> "$log_file"; fi
        ;;
    "err" | "error")
        echo -ne "${bred}[ERR][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -s "$log_file" ]; then echo "$(date +'%Y-%m-%d %H:%M:%S') - [ERR] $_message" >> "$log_file"; fi
        ;;
    "dbg" | "debug")
        if [ "$XXHECATE_DEBUG_MODE" -eq 1 ]; then
            echo -ne "${bcyan}[DEBUG][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
            if [ -s "$log_file" ]; then echo "$(date +'%Y-%m-%d %H:%M:%S') - [DEBUG] $_message" >> "$log_file"; fi
        fi
        ;;
    *)
        echo -ne "${bblue}[UNKNOWN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -s "$log_file" ]; then echo "$(date +'%Y-%m-%d %H:%M:%S') - [UNKNOWN] $_message" >> "$log_file"; fi
        ;;
    esac
}

function check_requirements() {
    for tool in "$@"; 
    do
        if ! command -v "$tool" &> /dev/null; 
        then
            log "Pre-requisite '$tool' was not found on your system." "ERROR"
            exit 1
        else
            log "Pre-requisite '$tool' found." "DEBUG"
        fi
    done
}

function load_env_file() {
    local _count=0
    log "Loading environment variables from the .env file." "INFO"
    if [ -f .env ]; then
        set -o allexport
        source .env
        set +o allexport
        while IFS= read -r _; do
            ((_count++))
        done < .env
        log "Loaded ${_count} environment variables from the .env file." "INFO"
    else
        log "The .env file was not found found falling back to defaults." "WARN"
    fi
}

function check_host_reachability_and_port() {
    local _host=$1
    local _port=$2
    local _timeout=5
    local _result
    log "Checking host $_host reachability and port $_port." "DEBUG"
    _result=$( nc -zv "$_host" "$_port" -w $_timeout 2>&1 )
    if [[ $_result == *"No route"* ]]; then
        log "Port $_port is not open on host (no route) $_host." "WARN"
        return 1
    elif [[ $_result == *"refused"* ]]; then 
        log "Port $_port is open on host (refused) $_host." "DEBUG"
        return 0
    elif [[ $_result == *"succeeded"* ]]; then
        log "Port $_port is open on host (succeeded) $_host." "DEBUG"
        return 0
    else
        log "Port $_port is not open on host (other) $_host." "WARN"
        return 1
    fi
}

function check_key_file() {
    local _keyfile=$1
    local _perms
    local first_digit
    log "Checking key file existance $_keyfile." "DEBUG"
    if [ ! -f "$_keyfile" ]; then
        log "Key file $_keyfile does not exist." "WARN"
        return 1
    fi
    # TODO: Implemenet proper permissions check.
    perms=$(stat -c %a "$_keyfile")
    first_digit=${perms:0:1}
    log "Key file $_keyfile has permissions: $perms." "DEBUG"
    if [[ "$first_digit" != "4" && "$first_digit" != "6" ]]; then
        log "Key file $_keyfile does not have correct owner permissions (expected 4 or 6 as the first digit)." "WARN"
        return 1
    fi
    return 0
}

function execute_remote_command() {
    local _host=$1
    local _user=$2
    local _password=$3
    local _port=$4
    local _keyfile=$5
    local _ssh_parameters
    local _ssh_cmd
    # TODO: Add checks if unlock is successful or not.
    _ssh_parameters="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    _command="printf %s $_password | cryptroot-unlock"
    log "Executing remote command on $_host:$_port." "DEBUG"
    # shellcheck disable=SC2206
    ssh_cmd=(ssh -n "${_user}@${_host}" -i "$_keyfile" -p "$_port" $_ssh_parameters)
    "${ssh_cmd[@]}" "$_command"
}

function main() {
    while IFS=, read -r _host _user _password _port _keyfile || [ -n "$_host" ]; do
        # TODO: Remove this insecure eval and replace with a proper expansion.
        _keyfile=$(eval echo "$_keyfile")
        if [ -z "$_host" ]; then
            log "Encountered an empty line or end of file." "DEBUG"
            continue  # Skip processing if the line is empty
        fi
        log "Processing host: $_host" "INFO"
        if check_host_reachability_and_port "$_host" "$_port"; then
            if check_key_file "$_keyfile"; then
                log "All checks passed for $_host. Executing unlock command" "INFO"
                execute_remote_command "$_host" "$_user" "$_password" "$_port" "$_keyfile"
            else
                log "Key file issues for $_host. Skipping..." "WARN"
            fi
        else
            log "Host $_host is not reachable. Skipping to next host..." "DEBUG"
        fi
    done < <(tail -n +2 "$XXHECATE_INVENTORY"; echo)
}

log "Starting $_SCRIPT_NAME $_SCRIPT_VERSION" "INFO"
load_env_file
check_requirements "nc" "ssh"
main
