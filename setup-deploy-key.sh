#!/usr/bin/env bash
set -euo pipefail
umask 077

# Usage: Run from the directory where you want the repository cloned.

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# POSIX-shell-safe quoting for Git's core.sshCommand, even if HOME has spaces.
shell_quote() {
    local escaped=${1//\'/\'\\\'\'}
    printf "'%s'" "$escaped"
}

for cmd in git ssh-keygen ssh; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
done

# 1. Read GitHub SSH URL.
read -r -p 'GitHub repository SSH URL: ' repo_url

# 2. Parse OWNER and REPO.
case "$repo_url" in
    git@github.com:*) repo_path=${repo_url#git@github.com:} ;;
    ssh://git@github.com/*) repo_path=${repo_url#ssh://git@github.com/} ;;
    *) fail 'Use a GitHub SSH URL (git@github.com:OWNER/REPO.git).' ;;
esac
repo_path=${repo_path%.git}

if [[ ! "$repo_path" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]]; then
    fail "Invalid GitHub repository path: $repo_path"
fi
owner=${repo_path%%/*}
repo_name=${repo_path##*/}
[[ "$repo_name" != '.' && "$repo_name" != '..' ]] || fail 'Invalid repository name.'
[[ ! -e "$repo_name" ]] || fail "Destination already exists: $repo_name"

printf '\nOwner: %s\nRepository: %s\n' "$owner" "$repo_name"

# 3. Detect configured proxy (environment first, Git global/system second).
proxy_url=''
proxy_source=''
for variable in https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY; do
    if [[ -n "${!variable:-}" ]]; then
        proxy_url=${!variable}
        proxy_source="environment ($variable)"
        break
    fi
done

if [[ -z "$proxy_url" ]]; then
    proxy_url=$(git config --global --get-urlmatch http.proxy "https://github.com/${repo_path}.git" 2>/dev/null || true)
    [[ -z "$proxy_url" ]] || proxy_source='Git global config'
fi
if [[ -z "$proxy_url" ]]; then
    proxy_url=$(git config --system --get-urlmatch http.proxy "https://github.com/${repo_path}.git" 2>/dev/null || true)
    [[ -z "$proxy_url" ]] || proxy_source='Git system config'
fi

proxy_mode=''
proxy_endpoint=''
if [[ -n "$proxy_url" ]]; then
    case "$proxy_url" in
        http://*) proxy_mode='connect'; proxy_endpoint=${proxy_url#http://} ;;
        socks5://*) proxy_mode='5'; proxy_endpoint=${proxy_url#socks5://} ;;
        socks5h://*) proxy_mode='5'; proxy_endpoint=${proxy_url#socks5h://} ;;
        https://*) fail 'HTTPS-to-proxy (https://...) is not supported by nc. Use an HTTP CONNECT proxy or another ProxyCommand.' ;;
        *://*) fail "Unsupported proxy protocol: $proxy_url" ;;
        *) proxy_mode='connect'; proxy_endpoint=$proxy_url ;;
    esac
    proxy_endpoint=${proxy_endpoint%/}
    if [[ ! "$proxy_endpoint" =~ ^[A-Za-z0-9._-]+:[0-9]{1,5}$ ]]; then
        fail 'Proxy must be host:port, http://host:port or socks5://host:port (no credentials).'
    fi
    proxy_port=${proxy_endpoint##*:}
    (( 10#$proxy_port >= 1 && 10#$proxy_port <= 65535 )) || fail 'Proxy port out of range.'
    command -v nc >/dev/null 2>&1 || fail 'Proxy detected, but nc is missing. On Ubuntu install netcat-openbsd.'
    printf 'Proxy: %s [%s]\n' "$proxy_endpoint" "$proxy_source"
else
    printf 'Proxy: not configured (direct SSH/22)\n'
fi

# 4. Create/reuse dedicated deploy key.
ssh_dir="$HOME/.ssh"
key_path="$ssh_dir/id_ed25519_deploy_${owner}_${repo_name}"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

if [[ -e "$key_path" || -e "${key_path}.pub" ]]; then
    [[ -f "$key_path" && -f "${key_path}.pub" ]] || fail 'Incomplete key pair. Resolve it manually; no files were overwritten.'
    printf 'Using existing key: %s\n' "$key_path"
else
    ssh-keygen -t ed25519 -f "$key_path" -C "deploy:${owner}/${repo_name}" -N ''
fi
chmod 600 "$key_path"
chmod 644 "${key_path}.pub"

printf '\n=== Deploy key (public key only) ===\n'
cat "${key_path}.pub"
printf '\nRegister this key in GitHub:\n'
printf 'https://github.com/%s/%s/settings/keys\n' "$owner" "$repo_name"
printf 'Choose "Allow write access" only if git push is required.\n'
printf 'Never paste or upload the private key.\n\n'

# 5. Wait for manual GitHub registration.
read -r -p 'After registering the deploy key, press Enter to clone (Ctrl-C to cancel): ' _

# 6. Construct repository-local SSH command.
ssh_command="ssh -i $(shell_quote "$key_path") -o IdentitiesOnly=yes"
if [[ -n "$proxy_url" ]]; then
    # GitHub SSH on port 443, tunneled through HTTP CONNECT or SOCKS5.
    proxy_command="ProxyCommand=nc -X ${proxy_mode} -x ${proxy_endpoint} %h %p"
    ssh_command+=" -o HostName=ssh.github.com -p 443 -o $(shell_quote "$proxy_command")"
fi

printf '\nCloning %s ...\n' "$repo_url"
# 'git clone -c' stores the setting in the new repository's .git/config.
git clone -c "core.sshCommand=$ssh_command" "$repo_url" "$repo_name"

printf '\n=== Done ===\n'
printf 'Directory: %s/%s\n' "$PWD" "$repo_name"
printf 'Private key: %s\n' "$key_path"
printf 'SSH command: %s\n' "$(git -C "$repo_name" config --local --get core.sshCommand)"
