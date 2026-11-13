# shellcheck shell=bash
# Shared helpers for every script in this repo. Source it, don't run it.
#
# The rule: nothing touches a cloud account unless --apply is given.
# Without it, a script prints the commands it would run and stops.
# Read-only calls are gated too, so a dry run never makes a network call.

FT_APPLY=0

# Dry-run output goes to fd 3, so a command printed inside $(...) still
# reaches the terminal instead of being captured.
exec 3>&1

ft_die() { printf 'error: %s\n' "$*" >&2; exit 2; }

ft_note() { printf '# %s\n' "$*" >&3; }

ft_common_usage() {
  cat <<'EOF'
Common options:
  --dry-run   print the commands and run nothing (the default)
  --apply     run them for real
  -h, --help  show this help
EOF
}

ft_banner() {
  if ((FT_APPLY)); then
    ft_note "APPLY: running commands against your account."
  else
    ft_note "dry run: nothing will be called or changed. Re-run with --apply to do it."
  fi
}

# Quote arguments so the printed line can be pasted back into a shell.
ft_quote() {
  local a sq="'" esc="'\\''" quoted=()
  for a in "$@"; do
    if [[ $a =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then
      quoted+=("$a")
    else
      quoted+=("'${a//$sq/$esc}'")
    fi
  done
  printf '%s\n' "${quoted[*]}"
}

# Print a step, then run it only with --apply.
#   ft_step "text to print" function [args...]
ft_step() {
  local text=$1
  shift
  if ((FT_APPLY)); then
    printf '+ %s\n' "$text" >&2
    "$@"
  else
    printf '%s\n' "$text" >&3
  fi
}

# Run a command (or print it).
ft_run() { ft_step "$(ft_quote "$@")" "$@"; }

# Run a command and discard its stdout, for commands that might print a
# credential (user creation, for example).
ft_run_quiet() { ft_step "$(ft_quote "$@") >/dev/null" _ft_quiet "$@"; }
_ft_quiet() { "$@" >/dev/null; }

# Run a command and print its stdout as the result. In a dry run, the
# placeholder is returned instead, so later steps print sensibly.
#   id=$(ft_capture '<vcn-id>' oci network vcn create ...)
ft_capture() {
  local placeholder=$1
  shift
  if ((FT_APPLY)); then
    printf '+ %s\n' "$(ft_quote "$@")" >&2
    "$@"
  else
    printf '%s\n' "$(ft_quote "$@")" >&3
    printf '%s' "$placeholder"
  fi
}

# Run a command with stdout going to a file created 0600. The output is
# never shown.
#   ft_to_file FILE cmd [args...]
ft_to_file() {
  local file=$1
  shift
  ft_step "$(ft_quote "$@") > $(ft_quote "$file")   # written 0600, never printed" \
    _ft_to_file "$file" "$@"
}
_ft_to_file() {
  local file=$1
  shift
  (umask 077 && "$@" >"$file")
  chmod 600 "$file"
}

ft_is_placeholder() { [[ -z $1 || $1 == *'<'* ]]; }

# With --apply, refuse to run while a value is still a placeholder.
#   ft_need "$PROJECT" --project
ft_need() {
  if ((FT_APPLY)) && ft_is_placeholder "$1"; then
    ft_die "$2 is required with --apply (got '${1}')"
  fi
}

ft_mode() {
  if stat -c %a "$1" >/dev/null 2>&1; then
    stat -c %a "$1"
  else
    stat -f %Lp "$1"
  fi
}

# A credential file must exist and be readable by its owner only.
ft_secret_file() {
  local f=$1 m
  [[ -f $f ]] || ft_die "no such file: $f"
  m=$(ft_mode "$f")
  [[ $m == 600 || $m == 400 ]] || ft_die "$f has mode $m; run: chmod 600 $f"
}

# A directory for generated credentials, owner-only.
ft_private_dir() {
  ft_step "mkdir -p -m 700 $(ft_quote "$1")" mkdir -p -m 700 "$1"
  if ((FT_APPLY)); then chmod 700 "$1"; fi
}

ft_need_cmd() {
  ((FT_APPLY)) || return 0
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || ft_die "missing command: $c"
  done
}
