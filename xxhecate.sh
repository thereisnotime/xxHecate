#!/bin/bash
#shellcheck disable=SC2002
# Load environment variables from .env file if it exists
_SCRIPT_VERSION="0.1.0"
_SCRIPT_NAME="xxHecate"

#####################################
#### Configuration
#####################################
INPUT_CSV="${INPUT_CSV:-inventory.csv}"
LOG_FILE="${LOG_FILE:-xxHecate.log}"
SLEEP_DURATION="${SLEEP_DURATION:-60}"

#####################################
#### Constants
#####################################
XXHECATE_DEBUG_FLAG=$(basename "$0/XXHECATE_DEBUG_MODE")
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
bblack='\e[1;30m'       # Black
bred='\e[1;31m'         # Red
bgreen='\e[1;32m'       # Green
byellow='\e[1;33m'      # Yellow
bblue='\e[1;34m'        # Blue
bpurple='\e[1;35m'      # Purple
bcyan='\e[1;36m'        # Cyan
bwhite='\e[1;37m'       # White
nc="\e[m"               # Color Reset
function log() {
    local _message="$1"
    local _level="$2"
    local _nl="\n"
	local _timestamp
	# check format
	if [ "$XXTOOLBELT_TIME_FORMAT" == "short" ]; then
		_timestamp=$(date +%H:%M:%S)
	else
		_timestamp=$(date +%d.%m.%Y-%d:%H:%M:%S-%Z)
	fi
    case $(echo "$_level" | tr '[:upper:]' '[:lower:]') in
    "info" | "information")
        echo -ne "${bwhite}[INFO][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${_nl}"
        ;;
    "warn" | "warning")
        echo -ne "${byellow}[WARN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${_nl}"
        ;;
    "err" | "error")
        echo -ne "${bred}[ERR][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${_nl}"
        ;;
	"dbg" | "debug")
		if [ "$XXTOOLBELT_DEBUG_MODE" -eq 1 ]; then
			echo -ne "${bcyan}[DEBUG][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${_nl}"
		fi
		;;
    *)
        echo -ne "${bblue}[UNKNOWN][${_SCRIPT_NAME} ${_SCRIPT_VERSION}][${_timestamp}]: ${_message}${nc}${_nl}"
        ;;
    esac
}

function failure() {
    local _lineno="$2"
    local _fn="$3"
    local _exitstatus="$4"
    local _msg="$5"
    local _lineno_fns="${1% 0}"
    if [[ "$_lineno_fns" != "0" ]]; then _lineno="${_lineno} ${_lineno_fns}"; fi
    log "Error in ${BASH_SOURCE[1]}:${_fn}[${_lineno}] Failed with status ${_exitstatus}: ${_msg}" "ERROR"
}

function load_env_file() {
  if [ -f .env ]; then
    export "$(cat .env | xargs)"
  fi
}

function log_message() {
  local _message
  _message="$1"
  if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; fi
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $_message" >> "$LOG_FILE"
  log "$_message" "INFO"
}

function validate_csv() {
  local csv_file="$1"
  local valid=true

  if [ "$XXHECATE_DEBUG_MODE" -eq 1 ]; then log "Validating CSV file $csv_file" "DEBUG"; fi
  while IFS=, read -r ip user password port key; do
    if [[ -z "$ip" || -z "$user" || -z "$password" || -z "$port" || -z "$key" ]]; then
      valid=false
      break
    fi
  done < "$csv_file"

  echo $valid
}

function load_and_validate_csv() {
  local csv_file="$1"
  if [ ! -f "$csv_file" ]; then
    log_message "CSV file $csv_file not found."
    return 1
  fi

  local is_valid
  is_valid=$(validate_csv "$csv_file")
  if [ "$is_valid" = false ]; then
    log_message "CSV file $csv_file is invalid."
    return 1
  fi

  return 0
}

function execute_ssh_command() {
  local ip="$1"
  local user="$2"
  local password="$3"
  local port="$4"
  local key="$5"

  log_message "Attempting to SSH into $user@$ip:$port"

  # Try to SSH into the server with a timeout
  ssh -o ConnectTimeout=10 -i "$key" -p "$port" "$user@$ip" "$REMOTE_COMMAND" &
  local ssh_status=$?

  if [ $ssh_status -eq 0 ]; then
    log_message "Successfully executed command on $user@$ip:$port"
  else
    log_message "Failed to connect to $user@$ip:$port"
  fi
}

function main_loop() {
  local last_valid_csv="$INPUT_CSV"

  while true; do
    load_and_validate_csv "$INPUT_CSV"
    local csv_status=$?

    if [ $csv_status -eq 0 ]; then
      last_valid_csv="$INPUT_CSV"
    else
      log_message "Using previous valid CSV file."
    fi

    while IFS=, read -r ip user password port key; do
      execute_ssh_command "$ip" "$user" "$password" "$port" "$key"
      sleep "$SLEEP_DURATION"
    done < "$last_valid_csv"

    sleep "$SLEEP_DURATION"
  done
}

#####################################
#### Main
#####################################
load_env_file
log "Starting $_SCRIPT_NAME $_SCRIPT_VERSION" "INFO"
main_loop