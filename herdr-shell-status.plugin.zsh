if (( $+functions[herdr_shell_status_disable] )); then
  herdr_shell_status_disable
fi

typeset -g _HERDR_SHELL_STATUS_ACTIVE=0
typeset -g _HERDR_SHELL_STATUS_BIN=""
typeset -g _HERDR_SHELL_STATUS_SOURCE="user:zsh-command"
typeset -g _HERDR_SHELL_STATUS_AGENT="cli"

if (( ! ${+HERDR_SHELL_STATUS_DELEGATES} )); then
  typeset -ga HERDR_SHELL_STATUS_DELEGATES=(
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
else
  typeset -ga HERDR_SHELL_STATUS_DELEGATES
fi

_herdr_shell_status_command_name() {
  emulate -L zsh
  setopt extendedglob

  local expanded_command="$1"
  local -a command_words
  command_words=( ${(z)expanded_command} )

  local command_index=1
  local command_word command_basename option_word
  local external_wrapper_seen=0
  while (( command_index <= ${#command_words} )); do
    command_word="${(Q)command_words[command_index]}"
    (( command_index++ ))
    if [[ "$command_word" == [A-Za-z_][A-Za-z0-9_]#=* ]]; then
      continue
    fi

    command_basename="${command_word:t}"
    case "$command_basename" in
      command|noglob)
        if (( external_wrapper_seen )); then
          print -r -- "$command_basename"
          return 0
        fi
        ;;
      exec)
        print -r -- "$command_basename"
        if (( external_wrapper_seen )); then
          return 0
        fi
        # Status 2 distinguishes the shell builtin from an executable named exec.
        return 2
        ;;
      env)
        external_wrapper_seen=1
        while (( command_index <= ${#command_words} )); do
          option_word="${(Q)command_words[command_index]}"
          case "$option_word" in
            --)
              (( command_index++ ))
              break
              ;;
            -i|--ignore-environment|-0|--null|--debug|-)
              (( command_index++ ))
              ;;
            -u|-C|-P|-S|--unset|--chdir|--split-string|--argv0)
              (( command_index += 2 ))
              ;;
            -u?*|-C?*|-P?*|-S?*|--unset=*|--chdir=*|--split-string=*|--argv0=*)
              (( command_index++ ))
              ;;
            --help|--version|-*)
              print -r -- "$command_basename"
              return 0
              ;;
            *)
              break
              ;;
          esac
        done
        ;;
      sudo)
        external_wrapper_seen=1
        while (( command_index <= ${#command_words} )); do
          option_word="${(Q)command_words[command_index]}"
          case "$option_word" in
            --)
              (( command_index++ ))
              break
              ;;
            -C|-D|-g|-h|-p|-R|-r|-T|-t|-U|-u|--chdir|--close-from|--group|--host|--other-user|--prompt|--role|--type|--user)
              (( command_index += 2 ))
              ;;
            -C?*|-D?*|-g?*|-h?*|-p?*|-R?*|-r?*|-T?*|-t?*|-U?*|-u?*|--chdir=*|--close-from=*|--group=*|--host=*|--other-user=*|--prompt=*|--role=*|--type=*|--user=*|--preserve-env=*)
              (( command_index++ ))
              ;;
            -A|-b|-E|-H|-i|-K|-k|-n|-P|-S|-s|--askpass|--background|--bell|--login|--non-interactive|--preserve-env|--preserve-groups|--remove-timestamp|--reset-timestamp|--shell|--stdin)
              (( command_index++ ))
              ;;
            -e|-l|-V|-v|--edit|--help|--list|--validate|--version|-*)
              print -r -- "$command_basename"
              return 0
              ;;
            *)
              break
              ;;
          esac
        done
        ;;
      time)
        if (( external_wrapper_seen )) || [[ "$command_word" != time ]]; then
          external_wrapper_seen=1
        fi
        while (( command_index <= ${#command_words} )); do
          option_word="${(Q)command_words[command_index]}"
          case "$option_word" in
            --)
              (( command_index++ ))
              break
              ;;
            -f|-o|--format|--output)
              (( command_index += 2 ))
              ;;
            -f?*|-o?*|--format=*|--output=*)
              (( command_index++ ))
              ;;
            -a|-h|-l|-p|-q|-v|--append|--portability|--quiet|--verbose)
              (( command_index++ ))
              ;;
            --help|--version|-*)
              print -r -- "$command_basename"
              return 0
              ;;
            *)
              break
              ;;
          esac
        done
        ;;
      *)
        print -r -- "$command_basename"
        return 0
        ;;
    esac
  done

  return 1
}

# Sets REPLY to the command text of a job spec, read in the current shell because subshells have no job table.
_herdr_shell_status_job_text() {
  emulate -L zsh
  REPLY=""
  zmodload zsh/parameter 2>/dev/null || return 1

  local job_spec="${1:-%+}" job_number="" job_key job_text
  case "$job_spec" in
    %|%%|%+)
      job_number="${(k)jobstates[(r)*:+:*]}"
      ;;
    %-)
      job_number="${(k)jobstates[(r)*:-:*]}"
      ;;
    %<->)
      job_number="${job_spec#%}"
      ;;
    %\?*)
      for job_key job_text in "${(@kv)jobtexts}"; do
        if [[ "$job_text" == *"${job_spec#%\?}"* ]]; then
          job_number="$job_key"
          break
        fi
      done
      ;;
    %*)
      for job_key job_text in "${(@kv)jobtexts}"; do
        if [[ "$job_text" == "${job_spec#%}"* ]]; then
          job_number="$job_key"
          break
        fi
      done
      ;;
    *)
      return 1
      ;;
  esac

  [[ -n "$job_number" && -n "${jobtexts[$job_number]:-}" ]] || return 1
  REPLY="${jobtexts[$job_number]}"
}

# Status 0 means some simple command in the list hands the pane to an agent.
_herdr_shell_status_delegates_command() {
  emulate -L zsh

  local -a command_words segment_words
  command_words=( ${(z)1} "" )

  local command_word command_name command_name_status REPLY
  for command_word in "${command_words[@]}"; do
    case "$command_word" in
      ''|'&&'|'||'|';'|'|'|'|&'|'&'|'&|'|'&!'|';|'|';;'|'('|')'|'{'|'}'|'!'|$'\n')
        if (( ${#segment_words} )); then
          command_name_status=0
          command_name="$(_herdr_shell_status_command_name "${(j: :)segment_words}")" || command_name_status=$?
          if (( command_name_status == 2 )) || (( ${HERDR_SHELL_STATUS_DELEGATES[(Ie)$command_name]} )); then
            return 0
          fi

          # A resumed job is delegated when the command that started it is.
          REPLY=""
          if [[ "$command_name" == fg ]]; then
            _herdr_shell_status_job_text "${(Q)segment_words[${segment_words[(i)fg]}+1]}"
          elif [[ "$command_name" == %* ]]; then
            _herdr_shell_status_job_text "$command_name"
          fi
          if [[ -n "$REPLY" ]] && _herdr_shell_status_delegates_command "$REPLY"; then
            return 0
          fi
        fi
        segment_words=()
        ;;
      *)
        segment_words+=( "$command_word" )
        ;;
    esac
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

  if _herdr_shell_status_delegates_command "$2"; then
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

  if (( command_status == 0 )); then
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
  if ! (( $+commands[jq] )); then
    print -u2 -r -- "herdr-shell-status: jq not found; command status reporting disabled"
    return 1
  fi

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
  herdr_shell_status_enable || true
fi
