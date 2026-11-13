#!/usr/bin/env bash
# Fail if anything in the tree looks like a credential or an account
# identifier. Crude on purpose: a false positive costs a minute, a leak
# costs a rotation.
#
#   scripts/secret-scan.sh            scan tracked files
#   scripts/secret-scan.sh --history  also scan every commit
set -euo pipefail
cd "$(dirname "$0")/.."

# Patterns are written so this file doesn't match itself.
patterns=(
  'ocid1[.][a-z0-9]+[.]oc[0-9]+[.][a-z0-9-]*[.][a-z0-9]{20,}'   # OCI resource IDs
  'A[K]IA[0-9A-Z]{16}'                                          # AWS-style access key IDs
  '-{5}BEGIN [A-Z ]*PRIVATE KEY-{5}'                            # private keys
  'aiven[v]1 [A-Za-z0-9+/=]{20,}'                               # Aiven auth header with a token
  '(password|passwd|secret|token|api_key)[ ]*[:=][ ]*["'\'']?[A-Za-z0-9+/_-]{12,}'  # assigned literal secrets
  'gh[p]_[A-Za-z0-9]{30,}'                                      # GitHub tokens
  'xox[b]-[A-Za-z0-9-]{20,}'                                    # Slack tokens
  '@g[m]ail[.]com'                                              # personal email addresses
)

# IPv4 addresses, except documentation, private, loopback and any-address
# ranges, which the scripts use on purpose.
ip_pattern='([0-9]{1,3}[.]){3}[0-9]{1,3}'
ip_allowed='^(0[.]0[.]0[.]0|127[.]|10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.]|192[.]0[.]2[.]|198[.]51[.]100[.]|203[.]0[.]113[.])'

found=0

scan() { # $1 = label, stdin = text with "file:line:content"
  local label=$1 text p
  text=$(cat)
  for p in "${patterns[@]}"; do
    if grep -E -i -- "$p" <<<"$text" | grep -v '^scripts/secret-scan.sh:'; then
      echo "^ $label: matches /$p/" >&2
      found=1
    fi
  done
  while IFS= read -r line; do
    local ip
    while IFS= read -r ip; do
      [[ $ip =~ $ip_allowed ]] && continue
      echo "$line"
      echo "^ $label: IP address $ip" >&2
      found=1
    done < <(grep -Eo -- "$ip_pattern" <<<"${line#*:*:}")
  done < <(grep -E -- "$ip_pattern" <<<"$text" | grep -v '^scripts/secret-scan.sh:' || true)
}

# Process substitution, not a pipe: scan must run in this shell to set $found.
scan "tracked files" < <(git ls-files -z | xargs -0 grep -n -I -H -E '.' -- 2>/dev/null)

if [[ ${1:-} == --history ]]; then
  scan "git history" < <(git log -p --all --format='commit %H%n%an <%ae>%n%B' | sed 's/^/history:0:/')
fi

if ((found)); then
  echo "secret scan: FAILED" >&2
  exit 1
fi
echo "secret scan: clean"
