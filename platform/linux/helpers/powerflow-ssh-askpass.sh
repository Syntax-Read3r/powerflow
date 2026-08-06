#!/bin/sh

# stdout is OpenSSH's private askpass pipe. All human-facing text goes directly
# to the controlling terminal so the password never enters PowerShell's streams.
terminal=/dev/tty
alias_name=${POWERFLOW_SRV_ALIAS:-server}

if [ ! -r "$terminal" ] || [ ! -w "$terminal" ]; then
    exit 1
fi

old_state=$(stty -g < "$terminal") || exit 1
trap 'stty "$old_state" < /dev/tty 2>/dev/null; unset password' EXIT HUP INT TERM

printf "Password for '%s': " "$alias_name" > "$terminal"
stty -echo < "$terminal" || exit 1
IFS= read -r password < "$terminal"
status=$?
stty "$old_state" < "$terminal"
printf '\n' > "$terminal"

[ "$status" -eq 0 ] || exit 1
printf '%s\n' "$password"
unset password
exit 0
