typeset -ga HERDR_SHELL_STATUS_DELEGATES
typeset -g _HERDR_SHELL_STATUS_ACTIVE=0
typeset -g _HERDR_SHELL_STATUS_BIN=""
typeset -g _HERDR_SHELL_STATUS_SOURCE="user:zsh-command"
typeset -g _HERDR_SHELL_STATUS_AGENT="cli"

if (( ${#HERDR_SHELL_STATUS_DELEGATES} == 0 )); then
  HERDR_SHELL_STATUS_DELEGATES=(
    amp
    claude
    codex
    copilot
    cursor-agent
    devin
    droid
    gemini
    grok
    hermes
    herdr-run
    kilo
    kimi
    kiro
    maki
    mastracode
    omp
    opencode
    pi
    qodercli
  )
fi

_herdr_shell_status_command_name() {
  emulate -L zsh
  setopt extendedglob

  local expanded_command="$1"
  local -a command_words
  command_words=( ${(z)expanded_command} )

  local command_word
  for command_word in "${command_words[@]}"; do
    command_word="${(Q)command_word}"
    if [[ "$command_word" == [A-Za-z_][A-Za-z0-9_]#=* ]]; then
      continue
    fi
    if [[ "$command_word" == command || "$command_word" == noglob ]]; then
      continue
    fi
    print -r -- "${command_word:t}"
    return 0
  done

  return 1
}

_herdr_shell_status_release() {
  emulate -L zsh
  [[ -n "$_HERDR_SHELL_STATUS_BIN" ]] || return 0
  "$_HERDR_SHELL_STATUS_BIN" pane release-agent "$HERDR_PANE_ID" \
    --source "$_HERDR_SHELL_STATUS_SOURCE" \
    --agent "$_HERDR_SHELL_STATUS_AGENT" >/dev/null 2>&1 || true
}

_herdr_shell_status_preexec() {
  emulate -L zsh

  local command_name
  command_name="$(_herdr_shell_status_command_name "$2")" || command_name=""

  if [[ "$command_name" == exec ]] || (( ${HERDR_SHELL_STATUS_DELEGATES[(Ie)$command_name]} )); then
    _HERDR_SHELL_STATUS_ACTIVE=0
    _herdr_shell_status_release
    return 0
  fi

  if "$_HERDR_SHELL_STATUS_BIN" pane report-agent "$HERDR_PANE_ID" \
    --source "$_HERDR_SHELL_STATUS_SOURCE" \
    --agent "$_HERDR_SHELL_STATUS_AGENT" \
    --state working >/dev/null 2>&1; then
    _HERDR_SHELL_STATUS_ACTIVE=1
  else
    _HERDR_SHELL_STATUS_ACTIVE=0
  fi

  return 0
}

_herdr_shell_status_precmd() {
  local command_status=$?
  emulate -L zsh

  (( _HERDR_SHELL_STATUS_ACTIVE )) || return 0
  _HERDR_SHELL_STATUS_ACTIVE=0

  if (( command_status == 0 || command_status == 130 || command_status == 137 || command_status == 143 )); then
    "$_HERDR_SHELL_STATUS_BIN" pane report-agent "$HERDR_PANE_ID" \
      --source "$_HERDR_SHELL_STATUS_SOURCE" \
      --agent "$_HERDR_SHELL_STATUS_AGENT" \
      --state idle >/dev/null 2>&1 || true
  else
    "$_HERDR_SHELL_STATUS_BIN" pane report-agent "$HERDR_PANE_ID" \
      --source "$_HERDR_SHELL_STATUS_SOURCE" \
      --agent "$_HERDR_SHELL_STATUS_AGENT" \
      --state blocked \
      --message "command exited with status $command_status" >/dev/null 2>&1 || true
  fi

  return 0
}

_herdr_shell_status_zshexit() {
  emulate -L zsh
  _HERDR_SHELL_STATUS_ACTIVE=0
  _herdr_shell_status_release
}

herdr_shell_status_disable() {
  emulate -L zsh
  autoload -Uz add-zsh-hook
  add-zsh-hook -d preexec _herdr_shell_status_preexec 2>/dev/null || true
  add-zsh-hook -d precmd _herdr_shell_status_precmd 2>/dev/null || true
  add-zsh-hook -d zshexit _herdr_shell_status_zshexit 2>/dev/null || true
  _HERDR_SHELL_STATUS_ACTIVE=0
  _herdr_shell_status_release
}

herdr_shell_status_enable() {
  emulate -L zsh

  [[ -o interactive ]] || return 1
  [[ "${HERDR_ENV:-}" == 1 && -n "${HERDR_PANE_ID:-}" ]] || return 1
  (( $+commands[jq] )) || return 1

  if [[ -n "${HERDR_BIN_PATH:-}" && -x "$HERDR_BIN_PATH" ]]; then
    _HERDR_SHELL_STATUS_BIN="$HERDR_BIN_PATH"
  elif (( $+commands[herdr] )); then
    _HERDR_SHELL_STATUS_BIN="${commands[herdr]}"
  else
    return 1
  fi

  local process_information shell_pid
  process_information="$("$_HERDR_SHELL_STATUS_BIN" pane process-info --pane "$HERDR_PANE_ID" 2>/dev/null)" || return 1
  shell_pid="$(jq -er '.result.process_info.shell_pid' <<< "$process_information" 2>/dev/null)" || return 1
  [[ "$shell_pid" == "$$" ]] || return 1

  autoload -Uz add-zsh-hook
  add-zsh-hook -d preexec _herdr_shell_status_preexec 2>/dev/null || true
  add-zsh-hook -d precmd _herdr_shell_status_precmd 2>/dev/null || true
  add-zsh-hook -d zshexit _herdr_shell_status_zshexit 2>/dev/null || true
  add-zsh-hook preexec _herdr_shell_status_preexec
  add-zsh-hook precmd _herdr_shell_status_precmd
  add-zsh-hook zshexit _herdr_shell_status_zshexit
}

if [[ -o interactive ]]; then
  herdr_shell_status_enable 2>/dev/null || true
fi
