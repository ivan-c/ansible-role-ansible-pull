#!/bin/sh -e


cmdname="$(basename "$0")"
bin_path="$(cd "$(dirname "$0")" && pwd)"
repo_path="${bin_path}/.."


usage() {
    cat << USAGE >&2
Usage:
    $cmdname [-h|--help] [ansible-pull options]
    -h     Show this help message
    Wrapper for ansible-pull
    Install dependencies with ansible-galaxy and run ansible-pull with defaults
USAGE
    exit 1
}

die(){
    printf '%s\n' "$1" >&2
    exit 1
}

ensure_checkout() {
    # invoke `ansible-pull --check` to setup VCS repository
    local repo_url="$1"
    local checkout_dir="$2"
    local pull_args="$3"
    if [ -d "$checkout_dir" ]; then
        return
    fi
    echo "Setting up checkout..."
    output=$(ansible-pull \
        --url "$repo_url" \
        --directory "$checkout_dir" \
        $ARGS \
        --check \
    ) || exit_code=$?
    if [ ! -d "$checkout_dir" ] && [ $exit_code != 0 ]; then
        echo Failed to create checkout at $checkout_dir
        die "$output"
    fi
}

install_roles() {
    # install roles required by ansible repository
    local repo_url="$1"
    local checkout_dir="$2"
    local pull_args="$3"
    ensure_checkout "$repo_url" "$checkout_dir" "$pull_args"
    echo "Updating roles..."
    ansible-galaxy install --role-file="$checkout_dir"/requirements.yaml
}

# override $HOME if running via sudo
if [ "$USER" = root ]; then
    HOME=/root
fi

hostname="$(hostname)"
default_checkout_dir="${HOME}/.ansible/pull/${hostname}"

# copy arguments; option parsing is destructive
ARGS=$@

# parse arguments before passing to ansible-galaxy
# argument parsing required as ansible-galaxy uses different option names than ansible-pull
while :; do
    case $1 in

        # handle checkout dir option
        -d|--directory)
            test "$2" || die "ERROR: $1 requires a non-empty option argument."
            checkout_dir=$2
            shift
            ;;
        -d*)
            # Delete "-d" and assign the remainder
            checkout_dir=${1#*-d}
            ;;

        --directory=?*)
            # Delete everything up to "=" and assign the remainder
            checkout_dir=${1#*=}
            ;;


        # handle VCS branch option
        -C|--checkout)
            test "$2" || die "ERROR: $1 requires a non-empty option argument."
            repo_ref=$2
            shift
            ;;
        -C*)
            # Delete "-d" and assign the remainder
            repo_ref=${1#*-C}
            ;;

        --checkout=?*)
            # Delete everything up to "=" and assign the remainder
            repo_ref=${1#*=}
            ;;


        # handle repo URL option
        -U|--url)
            test "$2" || die "ERROR: $1 requires a non-empty option argument."
            repo_url=$2
            shift
            ;;
        -U*)
            repo_url=${1#*-U}
            ;;
        --url=?*)
            repo_url=${1#*=}
            ;;


        -h|-\?|--help)
            usage
            exit
            ;;
        "")
            # no more options
            break
            ;;
    esac
    shift
done

# add user-installed paths
PATH="${PATH}:/usr/local/bin:${HOME}/.local/bin"


# precedence: environment variable, commandline option, default
checkout_dir="${ANSIBLE_PULL_DIRECTORY:-${checkout_dir:-$default_checkout_dir}}"


# TODO assign by filename pattern
export ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-"$checkout_dir"/hosts.ini}"

default_repo_url="$(cd "$checkout_dir" 2> /dev/null && git remote get-url origin || true)"
repo_url="${ANSIBLE_PULL_URL:-${repo_url:-$default_repo_url}}"


repo_ref="${ANSIBLE_PULL_CHECKOUT:-$repo_ref}"
if [ -n "$repo_ref" ]; then
    ARGS="${ARGS} --checkout ${repo_ref}"
fi


install_roles "$repo_url" "$checkout_dir" "$ARGS"

# if current machine explicitly listed in inventory
# limit ansible-pull plays to current machine
ensure_checkout "$repo_url" "$checkout_dir"
if [ -f "$ANSIBLE_INVENTORY" ] && grep --quiet "$hostname" "$ANSIBLE_INVENTORY"; then
    limit_opt="--limit $hostname"
fi

ansible-pull \
    $limit_opt \
    --url "$repo_url" \
    --directory "$checkout_dir" \
    --extra-vars ansible_python_interpreter=python3 \
    $ARGS
