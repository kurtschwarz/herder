set shell := ["zsh", "-cu"]

# Recipes take the path to an app or service, e.g. `just build apps/herder`.
# Each one owns a justfile with the same recipe names, so the root stays generic as
# apps and services with different toolchains land beside each other.

# Show available recipes
default:
    @just --list --unsorted

# Build DIR
build dir: (_in dir "build")

# Run DIR's tests
test dir *args: (_in dir "test" args)

# Build and run DIR
dev dir: (_in dir "dev")

# Set up DIR in a fresh clone
bootstrap dir: (_in dir "bootstrap")

# Remove DIR's build artifacts
clean dir: (_in dir "clean")

# Run any other recipe in DIR, e.g. `just in apps/herder uitest`
in dir recipe *args: (_in dir recipe args)

# Run every app and service's tests
test-all:
    #!/usr/bin/env zsh
    set -euo pipefail
    setopt null_glob
    for justfile in apps/*/justfile services/*/justfile packages/*/justfile; do
        dir=${justfile:h}
        print -P "%F{cyan}==> ${dir}%f"
        just --justfile "${justfile}" --working-directory "${dir}" test
    done

# List the apps and services in this repo
list:
    #!/usr/bin/env zsh
    setopt null_glob
    for justfile in apps/*/justfile services/*/justfile packages/*/justfile; do
        print -r -- "${justfile:h}"
    done

# Forward a recipe to DIR's own justfile
#
# Ctrl-C reaches this recipe's shell too, so it is trapped here as well. Without
# the trap this layer dies by signal and reports a long-running recipe like
# `just dev` as a failure. Any other exit code passes straight through.
[private]
_in dir recipe *args:
    #!/usr/bin/env zsh
    set -uo pipefail
    if [[ ! -f "{{ dir }}/justfile" ]]; then
        print -u2 "no justfile in {{ dir }} (try: just list)"
        exit 1
    fi

    trap 'exit 0' INT TERM HUP
    just --justfile "{{ dir }}/justfile" --working-directory "{{ dir }}" {{ recipe }} {{ args }}
    code=$?

    # 130 is Ctrl-C, which `just dev` treats as a normal way to stop.
    if (( code == 130 )); then
        code=0
    fi
    exit ${code}
