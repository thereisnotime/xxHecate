#!/bin/bash
#shellcheck disable=SC2002,SC1091
# TODO: Finish CSV validation and add IP TCP connection check, port validation, key file existence and permissions validation.
# TODO: Add execution of the cryptsetup-unlock script on the remote host.
# NOTE: Editing the inventory does not need a restart, the script will pick up the changes in the next iteration.
# NOTE: Editing the .env file will not take effect until the script is restarted.
_SCRIPT_VERSION="0.1.0"
_SCRIPT_NAME="xxHecate"

#####################################
#### Configuration
#####################################
XXHECATE_INVENTORY="${XXHECATE_INVENTORY:-inventory.csv}"
XXHECATE_LOG_FILE="${XXHECATE_LOG_FILE:-xxHecate.log}"
XXHECATE_SLEEP_DURATION="${XXHECATE_SLEEP_DURATION:-60}"
# TODO: Remove this after testing is done.
REMOTE_COMMAND="whois"

#####################################
#### Constants
#####################################
XXHECATE_DEBUG_FLAG="${XXHECATE_DEBUG_FLAG:-$(basename "${0^^}")_DEBUG_MODE}"
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

function load_env_file() {
  local _count=0
    if [ -f .env ]; then
        set -o allexport
        source .env
        set +o allexport
        # count number of variables loaded
        while IFS= read -r _; do
            ((_count++))
        done < .env
        log "Loaded ${_count} environment variables from the .env file." "INFO"
    else
        log "The .env file was not found found falling back to defaults." "WARN"
    fi
}

function validate_and_load_csv() {
  local csv_file="$1"
  local valid=true
  local count=0

  log "Starting validation and loading of Inventory CSV file $csv_file" "DEBUG"

  if [ ! -f "$csv_file" ]; then
    log "Inventory CSV file $csv_file not found." "ERROR"
    return 1
  fi

  if [ ! -s "$csv_file" ]; then
    log "Inventory CSV file $csv_file is empty." "ERROR"
    return 1
  fi

  while IFS=, read -r ip user password port key; do
    if [[ -z "$ip" || -z "$user" || -z "$password" || -z "$port" || -z "$key" ]]; then
      log "Invalid CSV entry found. One or more fields are missing." "ERROR"
      valid=false
      break
    fi
    ((count++))
  done < "$csv_file"

  if [ "$valid" = false ]; then
    log "Inventory file $csv_file contains invalid data." "ERROR"
    return 1
  fi

  log "Inventory file $csv_file is valid and contains $count hosts." "INFO"
  cat "$csv_file"
}

function execute_ssh_command() {
  local ip="$1"
  local user="$2"
  local password="$3"
  local port="$4"
  local key="$5"

  log "Executing command on $user@$ip:$port" "DEBUG"

  ssh -o ConnectTimeout=10 -i "$key" -p "$port" "$user@$ip" "$REMOTE_COMMAND" 2>/dev/null
  local ssh_status=$?

  if [ $ssh_status -eq 0 ]; then
    log "Successfully executed command on $user@$ip:$port" "INFO"
  else
    log "Failed to connect to $user@$ip:$port, skipping..." "WARN"
  fi
}

function main_loop() {
    while true; do
        while IFS=, read -r ip user password port key; do
            if [ -z "$ip" ]; then
                log "No valid CSV ($XXHECATE_INVENTORY) or empty file found, exiting..." "ERROR"
                exit 1
            fi
            # execute_ssh_command "$ip" "$user" "$password" "$port" "$key"
            log "Executing command on $user@$ip:$port" "DEBUG"
            sleep "$XXHECATE_SLEEP_DURATION"
        done < <(validate_and_load_csv "$XXHECATE_INVENTORY")
        
        sleep "$XXHECATE_SLEEP_DURATION"
    done
}

#####################################
#### Main
#####################################
log "Starting $_SCRIPT_NAME $_SCRIPT_VERSION" "INFO"
load_env_file
main_loop
