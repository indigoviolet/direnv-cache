# shellcheck disable=SC2155
# shellcheck disable=SC1090

# Main entry point

# [[file:README.org::*Main entry point][Main entry point:1]]
use_cache() {
    [[ -v DIRENV_CACHE_IGNORE ]] && {
        _debug "Ignoring cache, DIRENV_CACHE_IGNORE is set"
        return
    }
    [[ ${DIRENV_CACHE_DEBUG:-0} -gt 1 ]] && {
        set_x
        set -uo pipefail
    }
    local cache_filename=${1:-.env}
    local cache_file=$(get_cache_file "$cache_filename")

    # if cache exists and nonzero
    if [[ -s "$cache_file" ]]; then
        # Load preemptively
        load_cache "$cache_file"
        # Then verify (and reload if necessary)
        verify_cache "$cache_file"
    else
        _debug "Rebuilding cache: ${cache_file} missing or zero"
        build_and_load_cache "$cache_file"
    fi
    exit $?
}
# Main entry point:1 ends here

# Get cache file

# [[file:README.org::*Get cache file][Get cache file:1]]
get_cache_file() {
    # Ensure the cache file is in the same directory as the RC file
    local cache_filename=${1:?"Cache filename is required"}
    local rcfile=$(find_up ".envrc")
    builtin echo -n "${rcfile%%/.*}/$cache_filename"
}
# Get cache file:1 ends here

# Cache validity


# [[file:README.org::*Cache validity][Cache validity:1]]
verify_cache () {
    local cache_file=${1:?"Cache file required"}

    # runs direnv current for all .path in $DIRENV_WATCHES (in parallel)
    # xargs will return 0 only if the command is successful for all inputs
    direnv show_dump "$DIRENV_WATCHES" | jq -r '.[]|.path' | xargs -n1 -P0 direnv current
    local status=$?
    if [[ $status -gt 0 ]]; then
        _debug "Cache is stale, rebuilding"
        build_and_load_cache "$cache_file"
    fi
}
# Cache validity:1 ends here

# Build cache


# [[file:README.org::*Build cache][Build cache:1]]
build_cache() {
    local cache_file=${1:?"Cache file required"}
    if [[ -v DIRENV_CACHE_DEBUG ]]; then
        local stderr_file=$(mktemp)
    else
        local stderr_file=/dev/null
    fi

    # we use json/jq because the bash export uses $'' c-strings which are not
    # easy to get rid of with sed
    # DIRENV_LOG_FORMAT='' will turn off direnv logging
    # DIRENV_CACHE_IGNORE=1 so that we can build the cache without using it
    local cache_contents=$(
        set -o pipefail
        env DIRENV_CACHE_IGNORE=1 DIRENV_LOG_FORMAT="" direnv export json 2>"$stderr_file" | jq -r 'to_entries | map("export \(.key)=\(.value|@sh)")[]'
    )

    local status=$?
    if [[ -v DIRENV_CACHE_DEBUG ]]; then
        local stderr_content=$(<"$stderr_file") && rm "$stderr_file"
    else
        local stderr_content=""
    fi
    if [[ $status -eq 0 ]]; then
        _debug "Built cache: ${cache_file} contents: <${cache_contents}> stderr: <$stderr_content>"
        builtin echo -n "$cache_contents" >"$cache_file" || _debug "Cache build failed while writing to $cache_file"
        return
    else
        _debug "Cache build failed: $stderr_content"
        return $status
    fi
}
# Build cache:1 ends here

# Load cache


# [[file:README.org::*Load cache][Load cache:1]]
load_cache() {
    local cache_file=${1:?"Cache file required"}
    # we could use dotenv instead, but we don't need `watch_file`, and this is compatible?
    source "$cache_file" || {
        _debug "Cache load failed: $cache_file"
        exit $?
    }
    _debug "Loaded from cache $cache_file"
}
# Load cache:1 ends here

# build_and_load


# [[file:README.org::*build_and_load][build_and_load:1]]
build_and_load_cache() {
    local cache_file=${1:?"Cache file required"}
    build_cache "$cache_file" || {
        _debug "Cache build failed"
        exit $?
    }
    load_cache "$cache_file"
}
# build_and_load:1 ends here

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
