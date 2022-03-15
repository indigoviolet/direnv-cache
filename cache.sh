# shellcheck disable=SC2155

# Main entry point

# [[file:cache.org::*Main entry point][Main entry point:1]]
use_cache() {
    # show_dump $DIRENV_WATCHES

    [[ -v DIRENV_CACHE_IGNORE ]] && {
        _debug "Ignoring cache, DIRENV_CACHE_IGNORE is set"
        return
    }
    [[ -v DIRENV_CACHE_DEBUG ]] && {
        set_x
        set -uo pipefail
    }

    local cache_file="${1:-$(pwd)/.env}"
    shift
    if ! cache_is_valid "$cache_file" "$@"; then
        build_cache "$cache_file" || {
            _debug "Cache build failed"
            exit $?
        }
    fi

    _debug "Loading from cache ${cache_file}"

    # watch_file
    dotenv_if_exists "$cache_file"
    exit 0
}
# Main entry point:1 ends here

# Check cache validity


# [[file:cache.org::*Check cache validity][Check cache validity:1]]
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


# [[file:cache.org::*Build cache][Build cache:1]]
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
    local direnv_export_cmd="${direnv} watch ${shell} ${cache_file} && ${direnv} export json"

    # DIRENV_LOG_FORMAT='' will turn off direnv logging
    # DIRENV_CACHE_IGNORE=1 so that we can build the cache without using it
    local cache_contents=$(env -i \
        --chdir "$working_dir" \
        HOME="$HOME" \
        DIRENV_CACHE_IGNORE=1 \
        DIRENV_LOG_FORMAT="" \
        "$shell" -ilc "$direnv_export_cmd" 2>"$stderr_file" |
                               jq -r 'to_entries | map("export \(.key)=\(.value)")[]')

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

# Is cache file the newest?


# [[file:cache.org::*Is cache file the newest?][Is cache file the newest?:1]]
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

# [[file:cache.org::*Debug printing][Debug printing:1]]
_debug() {
    # Return status of this function is always the previous status.
    #
    # Prints $1 if DIRENV_CACHE_DEBUG is set. (Note that you probably have to
    # ~export~ it, not just set it, since all this code runs in a subshell)
    local status=$?
    local msg=${1:?"Message required"}
    [[ -v DIRENV_CACHE_DEBUG ]] && echo "$msg (status: $status)" >&2
    return $status
}
# Debug printing:1 ends here

# Emacs local variables


# [[file:cache.org::*Emacs local variables][Emacs local variables:1]]
# Local Variables:
# sh-shell: bash
# End:
# Emacs local variables:1 ends here
