# shellcheck disable=SC2155

# Main entry point

# [[file:README.org::*Main entry point][Main entry point:1]]
use_cache() {
    # show_dump $DIRENV_WATCHES

    [[ -v DIRENV_CACHE_IGNORE ]] && {
        _debug "Ignoring cache, DIRENV_CACHE_IGNORE is set"
        return
    }
    [[ ${DIRENV_CACHE_DEBUG:-0} -gt 1 ]] && {
        set_x
        set -uo pipefail
    }
    echo "$DIRENV_WATCHES"
    local cache_file="${1:-$(pwd)/.env}"
    shift
    if ! cache_is_valid "$cache_file" "$@"; then
        build_cache "$cache_file" || {
            _debug "Cache build failed"
            exit $?
        }
    fi

    _debug "Loading from cache ${cache_file}"
    dotenv_if_exists "$cache_file"
    exit 0
}
# Main entry point:1 ends here

# Check cache validity


# [[file:README.org::*Check cache validity][Check cache validity:1]]
cache_is_valid() {
    # Checks cache validity, and returns 0 for valid cache, nonzero for invalid cache.
    #
    # * Parameters
    #
    # - cache_file
    # - dependency_files :: an optional list of files that the cache file must be newer than
    #
    # * Conditions for valid cache
    #
    # 1. DIRENV_CACHE_REBUILD is not set (set this to force rebuilds)
    # 2. cache file exists
    # 3. cache file is newer than dependency files

    [[ ! -v DIRENV_CACHE_REBUILD ]] || {
        _debug "Rebuilding cache, DIRENV_CACHE_REBUILD is set"
        return
    }

    local cache_file=${1:?"Cache file required"}
    [[ -f "$cache_file" ]] || {
        _debug "Cache invalid: $cache_file missing"
        return
    }
    is_newest "$@" || {
        _debug "Cache invalid: not newest"
        return
    }
    _debug "Cache is valid"
    true
}
# Check cache validity:1 ends here

# Build cache


# [[file:README.org::*Build cache][Build cache:1]]
build_cache() {
    # Builds the cache by calling ~direnv export~ in a clean login shell (which
    # is the "base" environment to diff against).
    #
    # * Parameters:
    #
    # - cache_file :: the dotenv file to cache into
    #
    # * Requirements:
    #
    # - jq :: to parse json export into dotenv format

    local cache_file=${1:?"Cache file required"}

    # We use the login shell to capture any user config in the baseline
    local shell=$(basename "$SHELL")
    local working_dir=$(dirname "$cache_file")
    local direnv=$(which direnv)

    if [[ -v DIRENV_CACHE_DEBUG ]]; then
        local stderr_file=$(mktemp)
    else
        local stderr_file=/dev/null
    fi

    # We first add the cache file to the watch list, and then export -- this
    # makes the cache file be included in DIRENV_WATCHES in the cached env.
    #
    # we use json/jq because the bash export uses $'' c-strings which are not
    # easy to get rid of with sed
    local direnv_export_cmd="${direnv} export json"

    # DIRENV_LOG_FORMAT='' will turn off direnv logging
    # DIRENV_CACHE_IGNORE=1 so that we can build the cache without using it
    local cache_contents=$(env -i \
        --chdir "$working_dir" \
        HOME="$HOME" \
        TERM="$TERM" \
        DIRENV_CACHE_IGNORE=1 \
        DIRENV_LOG_FORMAT="" \
        "$shell" -ilc "$direnv_export_cmd" 2>"$stderr_file" |
                               jq -r 'to_entries | map("export \(.key)=\(.value|@sh)")[]')

    local status=$?
    if [[ -v DIRENV_CACHE_DEBUG ]]; then
        local stderr_content=$(<"$stderr_file") && rm "$stderr_file"
    else
        local stderr_content=""
    fi
    if [[ $status -eq 0 ]]; then
        echo "$cache_contents" >"$cache_file"
        _debug "Built ${shell} cache for ${working_dir}: ${cache_file} contents: <${cache_contents}> stderr: <$stderr_content>"
        return
    else
        _debug "Cache build failed: $stderr_content"
        return $status
    fi
}
# Build cache:1 ends here

# Dependency files

# each time direnv enters the directory it has to load from .envrc

# but on each prompt, it only reloads if the watch list indicates that the env is stale



# [[file:README.org::*Dependency files][Dependency files:1]]
direnv show_dump $DIRENV_WATCHES | jq '.[].Path'
# Dependency files:1 ends here

# Is cache file the newest?


# [[file:README.org::*Is cache file the newest?][Is cache file the newest?:1]]
is_newest() {
    # Checks if cache_file is newer than all dependency files. Returns 0 if yes, nonzero if not.
    #
    # * Parameters
    #
    # - cache_file
    # - dependency files
    [[ $# -eq 1 ]] && {
        _debug "No dependencies"
        return
    }

    local cache_file=${1:?"Cache file required"}
    shift
    for f in "$@"; do
        [[ "$cache_file" -nt "$f" ]] || {
            _debug "Cache invalid: $cache_file is older than $f"
            return
        }
    done

    true
}
# Is cache file the newest?:1 ends here

# Debug printing

# [[file:README.org::*Debug printing][Debug printing:1]]
_debug() {
    # Return status of this function is always the previous status.
    #
    # Prints $1 if DIRENV_CACHE_DEBUG is set. (Note that you probably have to
    # ~export~ it, not just set it, since all this code runs in a subshell)

    {
        local status=$?
        [[ -o xtrace ]] && {
            shopt -uo xtrace
            local xtrace_was_on=1
        }
    } 2>/dev/null

    local msg=${1:?"Message required"}
    [[ -v DIRENV_CACHE_DEBUG ]] && echo "$msg (status: $status)" >&2

    {
        [[ ${xtrace_was_on:-0} -eq 1 ]] && shopt -so xtrace
        return $status
    } 2>/dev/null
}
# Debug printing:1 ends here

# Local Variables:
# sh-shell: bash
# End:
