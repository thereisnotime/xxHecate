#!/bin/bash
#shellcheck disable=SC2002,SC1091,SC2034
# TODO: Finish CSV validation and add IP TCP connection check, port validation, key file existence and permissions validation.
# NOTE: Editing the inventory does not need a restart, the script will pick up the changes in the next iteration.
# NOTE: Editing the .env file will not take effect until the script is restarted.
_SCRIPT_VERSION="0.3.0"
_SCRIPT_NAME="xxHecate"

#####################################
#### Configuration
#####################################
XXHECATE_SCRIPT_DIRECTORY="$(dirname "$(readlink -f "$0")")"
# Record which settings arrived from the real environment, before any defaults
# are applied below. load_env_file() leaves these alone, so precedence is
# environment > .env > default. Previously .env was sourced with allexport,
# which clobbered anything set on the command line.
XXHECATE_ENV_OVERRIDES=""
for _v in XXHECATE_INVENTORY XXHECATE_LOG_FILE XXHECATE_SLEEP_DURATION XXHECATE_LOOP XXHECATE_KNOWN_HOSTS; do
    if [ -n "${!_v:-}" ]; then XXHECATE_ENV_OVERRIDES="${XXHECATE_ENV_OVERRIDES} ${_v}"; fi
done
unset _v
XXHECATE_INVENTORY="${XXHECATE_INVENTORY:-${XXHECATE_SCRIPT_DIRECTORY}/inventory.csv}"
XXHECATE_LOG_FILE="${XXHECATE_LOG_FILE:-${XXHECATE_SCRIPT_DIRECTORY}/xxHecate.log}"
# Only used when XXHECATE_LOOP=1. One-shot runs (cron/systemd timer) ignore it.
XXHECATE_SLEEP_DURATION="${XXHECATE_SLEEP_DURATION:-60}"
# 0 = run the inventory once and exit (the default; correct for cron and for a
# systemd *timer*). 1 = loop forever, sleeping XXHECATE_SLEEP_DURATION between
# passes (for running as a long-lived service with no timer).
XXHECATE_LOOP="${XXHECATE_LOOP:-0}"
# Optional known_hosts file. When set, hosts unlocked over a *booted* OS (the
# truenas-zfs method) are verified against it instead of skipping host-key
# checking. The LUKS method cannot use this: an initramfs (dropbear) presents a
# different host key than the booted system, so it stays unverified by design.
XXHECATE_KNOWN_HOSTS="${XXHECATE_KNOWN_HOSTS:-}"

#####################################
#### Constants
#####################################
XXHECATE_DEBUG_FLAG="${_SCRIPT_NAME}_DEBUG_MODE"
XXHECATE_DEBUG_FLAG=$(echo "$XXHECATE_DEBUG_FLAG" | tr '[:lower:]' '[:upper:]')
XXHECATE_DEBUG_MODE=$(if [[ -f $XXHECATE_DEBUG_FLAG ]]; then echo 1; else echo 0; fi)

#####################################
#### Helpers
#####################################
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
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

    # NOTE: the guard is -f (file exists), not -s (file is non-empty). With -s
    # nothing was ever written: the file is created empty just above, so the
    # first append was always skipped and it never became non-empty.
    case $(echo "$_level" | tr '[:upper:]' '[:lower:]') in
    "info" | "information")
        echo -ne "${bwhite}[INFO][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -f "$log_file" ]; then echo "$_timestamp - [INFO] $_message" >> "$log_file"; fi
        ;;
    "warn" | "warning")
        echo -ne "${byellow}[WARN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -f "$log_file" ]; then echo "$_timestamp - [WARN] $_message" >> "$log_file"; fi
        ;;
    "err" | "error")
        echo -ne "${bred}[ERR][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -f "$log_file" ]; then echo "$_timestamp - [ERR] $_message" >> "$log_file"; fi
        ;;
    "dbg" | "debug")
        if [ "$XXHECATE_DEBUG_MODE" -eq 1 ]; then
            echo -ne "${bcyan}[DEBUG][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
            if [ -f "$log_file" ]; then echo "$_timestamp - [DEBUG] $_message" >> "$log_file"; fi
        fi
        ;;
    *)
        echo -ne "${bblue}[UNKNOWN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${nl}"
        if [ -f "$log_file" ]; then echo "$_timestamp - [UNKNOWN] $_message" >> "$log_file"; fi
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
    local _skipped=0
    local _line
    local _key
    local _value
    log "Loading environment variables from the .env file." "INFO"
    if [ -f .env ]; then
        while IFS= read -r _line || [ -n "$_line" ]; do
            # Skip blanks and comments.
            case "$_line" in "" | "#"*) continue ;; esac
            case "$_line" in *=*) ;; *) continue ;; esac
            _key=${_line%%=*}
            _value=${_line#*=}
            _key=$(echo "$_key" | tr -d '[:space:]')
            # Strip one layer of surrounding quotes.
            _value=${_value%\"}
            _value=${_value#\"}
            _value=${_value%\'}
            _value=${_value#\'}
            # An explicit environment value outranks the .env file.
            case " $XXHECATE_ENV_OVERRIDES " in
            *" $_key "*)
                log "Keeping environment value for $_key, ignoring the .env entry." "DEBUG"
                ((_skipped++))
                continue
                ;;
            esac
            export "$_key=$_value"
            ((_count++))
        done < .env
        log "Loaded ${_count} environment variables from the .env file (${_skipped} overridden by the environment)." "INFO"
    else
        log "The .env file was not found, falling back to defaults." "WARN"
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
    # NOTE: assigns to the declared local (_perms), not a stray global (perms).
    _perms=$(stat -c %a "$_keyfile")
    first_digit=${_perms:0:1}
    log "Key file $_keyfile has permissions: $_perms." "DEBUG"
    if [[ "$first_digit" != "4" && "$first_digit" != "6" ]]; then
        log "Key file $_keyfile does not have correct owner permissions (expected 4 or 6 as the first digit)." "WARN"
        return 1
    fi
    return 0
}

function ssh_parameters_for() {
    # $1 = "initramfs" (LUKS/dropbear) or "booted" (a running OS).
    #
    # An initramfs presents a different host key than the booted system, so the
    # LUKS path cannot verify it and stays lenient. A booted host has a stable
    # key, so it is verified whenever XXHECATE_KNOWN_HOSTS is configured.
    local _kind=$1
    local _params="-o LogLevel=ERROR -o ConnectTimeout=10"
    if [ "$_kind" = "booted" ] && [ -n "$XXHECATE_KNOWN_HOSTS" ]; then
        echo "$_params -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$XXHECATE_KNOWN_HOSTS"
    else
        echo "$_params -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    fi
}

function execute_remote_command() {
    local _host=$1
    local _user=$2
    local _password=$3
    local _port=$4
    local _keyfile=$5
    local _ssh_parameters
    local _result
    local _rc

    _ssh_parameters=$(ssh_parameters_for initramfs)

    # The passphrase is piped over the SSH channel into cryptroot-unlock rather
    # than interpolated into the remote command string. Interpolating it meant a
    # passphrase containing a space split into two arguments, and one containing
    # $, backticks or quotes was re-expanded by the remote shell. On stdin it is
    # passed verbatim and never appears in argv or shell history on either side.
    log "Executing remote command on $_host:$_port." "DEBUG"
    # shellcheck disable=SC2086
    _result=$(printf '%s\n' "$_password" | ssh "${_user}@${_host}" -i "$_keyfile" -p "$_port" \
        $_ssh_parameters "cryptroot-unlock" 2>&1)
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        log "LUKS unlock on $_host returned success." "INFO"
        return 0
    fi
    # A refused or immediately closed connection on the unlock port means the
    # initramfs SSH server is not listening, which is the normal state once a
    # host has finished booting - there is nothing to unlock. Logging that at
    # ERROR every pass would bury real failures, so it is reported as INFO.
    case "$_result" in
    *"Connection refused"* | *"Connection closed by"* | *"Connection reset by"*)
        log "Nothing to unlock on $_host: the unlock port is not listening (host already booted)." "INFO"
        return 0
        ;;
    esac
    log "LUKS unlock on $_host failed (rc=$_rc): $_result" "ERROR"
    return "$_rc"
}

function unlock_truenas_zfs() {
    local _host=$1
    local _user=$2
    local _password=$3
    local _port=$4
    local _keyfile=$5
    local _dataset=${6:-tank}
    local _ssh_parameters
    local _remote_py
    local _result
    local _rc

    # A TrueNAS is a booted OS with a stable host key, so this verifies it when
    # XXHECATE_KNOWN_HOSTS is set. LogLevel=ERROR keeps the "Permanently added
    # ... to the list of known hosts" notice out of the captured output so the
    # log line is just the JSON result.
    _ssh_parameters=$(ssh_parameters_for booted)
    if [ -z "$XXHECATE_KNOWN_HOSTS" ]; then
        log "XXHECATE_KNOWN_HOSTS is unset; sending the passphrase to $_host without host-key verification." "WARN"
    fi

    # Unlocks a TrueNAS (ZFS native encryption) dataset tree.
    #
    # Only the encryption root needs a passphrase: every child inherits its key
    # from it (encryptionroot == the root), so a single recursive unlock covers
    # the whole tree. Listing each child with the passphrase repeated is
    # redundant.
    #
    # The passphrase arrives on stdin, never in argv, so it is not exposed in
    # the process list on either side. pool.dataset.unlock is a middleware job,
    # so we wait for it (job=True) and report the real result rather than a job
    # id. The call is a no-op when the tree is already unlocked, which keeps it
    # safe to run on a timer.
    _remote_py='
import json, sys
from truenas_api_client import Client

dataset = sys.argv[1]
passphrase = sys.stdin.read().rstrip("\n")

with Client() as client:
    found = client.call("pool.dataset.query", [["id", "=", dataset]])
    if not found:
        print(json.dumps({"status": "missing", "dataset": dataset}))
        sys.exit(2)
    info = found[0]
    if not info.get("encrypted"):
        print(json.dumps({"status": "not-encrypted", "dataset": dataset}))
        sys.exit(0)
    if not info.get("locked"):
        print(json.dumps({"status": "already-unlocked", "dataset": dataset}))
        sys.exit(0)
    result = client.call(
        "pool.dataset.unlock",
        dataset,
        {"recursive": True, "datasets": [{"name": dataset, "passphrase": passphrase}]},
        job=True,
    )

unlocked = result.get("unlocked") or []
failed = result.get("failed") or {}
ok = bool(unlocked) and not failed
print(json.dumps({
    "status": "unlocked" if ok else "partial",
    "unlocked": unlocked,
    "failed": {k: (v or {}).get("error") for k, v in failed.items()},
}))
sys.exit(0 if ok else 1)
'
    log "Unlocking TrueNAS dataset tree '$_dataset' on $_host:$_port." "DEBUG"
    # Note: no -n here (unlike the LUKS path) because stdin carries the passphrase.
    # shellcheck disable=SC2086
    _result=$(printf '%s' "$_password" | ssh "${_user}@${_host}" -i "$_keyfile" -p "$_port" \
        $_ssh_parameters "python3 -c '$_remote_py' '$_dataset'" 2>&1)
    _rc=$?
    if [ "$_rc" -eq 0 ]; then
        log "TrueNAS unlock on $_host succeeded: $_result" "INFO"
    else
        log "TrueNAS unlock on $_host failed (rc=$_rc): $_result" "ERROR"
    fi
    return "$_rc"
}

function main() {
    while IFS=, read -r _host _user _password _port _keyfile _method _target || [ -n "$_host" ]; do
        # Expand a leading ~ and $HOME/${HOME} without eval. The old
        # `eval echo "$_keyfile"` executed whatever the inventory contained, so
        # a crafted key path could run arbitrary commands as the unlocker user.
        _keyfile=$(echo "$_keyfile" | tr -d '\r')
        _keyfile=${_keyfile/#\~/$HOME}
        _keyfile=${_keyfile//\$\{HOME\}/$HOME}
        _keyfile=${_keyfile//\$HOME/$HOME}
        # Optional columns. Absent (5-column inventory) means the LUKS method,
        # which keeps older inventories working unchanged. Trailing CR is
        # stripped so a CRLF inventory does not break the method match.
        _method=$(echo "${_method:-}" | tr -d '\r' | tr '[:upper:]' '[:lower:]')
        _target=$(echo "${_target:-}" | tr -d '\r')
        if [ -z "$_host" ]; then
            log "Encountered an empty line or end of file." "DEBUG"
            continue  # Skip processing if the line is empty
        fi
        log "Processing host: $_host" "INFO"
        if check_host_reachability_and_port "$_host" "$_port"; then
            if check_key_file "$_keyfile"; then
                log "All checks passed for $_host. Executing unlock command" "INFO"
                case "$_method" in
                "" | luks | cryptroot)
                    execute_remote_command "$_host" "$_user" "$_password" "$_port" "$_keyfile"
                    ;;
                truenas-zfs | truenas | zfs)
                    unlock_truenas_zfs "$_host" "$_user" "$_password" "$_port" "$_keyfile" "$_target"
                    ;;
                *)
                    log "Unknown unlock method '$_method' for $_host. Skipping..." "ERROR"
                    ;;
                esac
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

# One-shot by default, which is what cron and a systemd *timer* expect. Set
# XXHECATE_LOOP=1 to keep running and re-walk the inventory every
# XXHECATE_SLEEP_DURATION seconds instead (a long-lived service with no timer).
# Looping under a timer would stack overlapping runs, so it is opt-in.
if [ "$XXHECATE_LOOP" = "1" ]; then
    log "Loop mode enabled, re-running every ${XXHECATE_SLEEP_DURATION}s. Ctrl-C to stop." "INFO"
    while true; do
        main
        log "Pass complete, sleeping ${XXHECATE_SLEEP_DURATION}s." "DEBUG"
        sleep "$XXHECATE_SLEEP_DURATION"
    done
else
    main
fi
