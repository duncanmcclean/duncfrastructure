#!/usr/bin/env bash

set -euo pipefail
shopt -s inherit_errexit

prepare_firewall() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root." >&2
        exit 1
    fi

    if ! command -v ufw > /dev/null; then
        echo "ufw is not installed." >&2
        exit 1
    fi

    exec 9> /run/lock/duncfrastructure-firewall.lock
    flock 9
}

ufw_command() {
    if [[ -n ${DRY_RUN:-} ]]; then
        echo "[dry run] ufw $*"
        return
    fi

    ufw "$@" > /dev/null
}

fetch_ip_list() {
    local url
    local response

    for url in "$@"; do
        response=$(curl --fail --silent --show-error --location --max-time 30 "$url")

        if [[ -z $response ]]; then
            echo "$url returned an empty IP list." >&2
            exit 1
        fi

        while read -r ip; do
            [[ -z $ip ]] && continue

            if ! is_ip_address "$ip"; then
                echo "$url returned something that isn't an IP address: $ip" >&2
                exit 1
            fi

            echo "$ip"
        done <<< "$response"
    done
}

is_ip_address() {
    local ipv4='^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'
    local ipv6='^[0-9a-fA-F]*:[0-9a-fA-F:]*(/[0-9]{1,3})?$'

    [[ $1 =~ $ipv4 || $1 =~ $ipv6 ]]
}

sync_allowed_ips() {
    local tag=$1
    local ports=$2
    shift 2

    local ip
    local stale_ips=()
    local added_rules
    local existing_ips
    local existing_ip_count
    local desired_ips=("$@")
    added_rules=$(ufw show added)
    existing_ips=$(grep "comment '$tag'" <<< "$added_rules" | sed -E 's/.* from ([^ ]+) to .*/\1/' || true)
    existing_ip_count=$(grep --count . <<< "$existing_ips" || true)

    for ip in $existing_ips; do
        if ! printf '%s\n' "${desired_ips[@]}" | grep --quiet --line-regexp --fixed-strings "$ip"; then
            stale_ips+=("$ip")
        fi
    done

    if (( ${#stale_ips[@]} * 2 > existing_ip_count )); then
        echo "This would remove ${#stale_ips[@]} of the $existing_ip_count allowed IPs on port $ports, which looks wrong. Leaving the firewall alone." >&2
        exit 1
    fi

    for ip in "${desired_ips[@]}"; do
        if ! grep --quiet --line-regexp --fixed-strings "$ip" <<< "$existing_ips"; then
            echo "Allowing $ip on port $ports."
            ufw_command allow from "$ip" to any port "$ports" proto tcp comment "$tag"
        fi
    done

    for ip in "${stale_ips[@]}"; do
        echo "Removing $ip from port $ports."
        ufw_command delete allow from "$ip" to any port "$ports" proto tcp
    done
}

remove_public_rules() {
    local port=$1
    local rule
    local added_rules
    local public_rules
    added_rules=$(ufw show added)
    public_rules=$(grep -E "^ufw (allow|limit) $port(/tcp)?$" <<< "$added_rules" || true)

    while read -r rule; do
        [[ -z $rule ]] && continue

        echo "Removing public rule: $rule"
        ufw_command delete ${rule#ufw }
    done <<< "$public_rules"
}
