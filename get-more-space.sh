#!/usr/bin/env bash

cat <<'EOF'

 .88b  d88.  .d88b.  d8888b. d88888b     .d8888. d8888b.  .d8b.   .o88b. d88888b 
 88'YbdP`88 .8P  Y8. 88  `8D 88'         88'  YP 88  `8D d8' `8b d8P  Y8 88'     
 88  88  88 88    88 88oobY' 88ooooo     `8bo.   88oodD' 88ooo88 8P      88ooooo 
 88  88  88 88    88 88`8b   88¯¯¯¯        `Y8b. 88¯¯¯   88¯¯¯88 8b      88¯¯¯¯  
 88  88  88 `8b  d8' 88 `88. 88.         db   8D 88      88   88 Y8b  d8 88.     
 YP  YP  YP  `Y88P'  88   YD Y88888P     `8888Y' 88      YP   YP  `Y88P' Y88888P
                                ( more space )
EOF

################################################################################
# Configuring bash...
#
# NOTE: not globally setting `-eu` `-o pipefail` by design.
# This actions should be as transparent as possible, and will have many removals fail.
PS4=" $ "
#
################################################################################

MORE_SPACE_ACTION_TOP="${BASH_SOURCE[0]%/*}"

#
# Helpers
#

# Returns the (raw) value of a specified github action input.
_get_input() {
	local attr="$1"; shift
	local default="${1}"; shift
	printf "%s" "$INPUTS_JSON" | jq --raw-output '.[$attr] // $default' --arg attr "$attr" --arg default "$default"
}

# The non-verbose variant.
__enabled() {
	val="$(_get_input "$@" "true")"
	[[ "$val" == "true" ]]
}

# This maybe-verbose variant prints the check when verbose.
_enabled() {
	local val
	if __enabled "verbose"; then
		val="$(_get_input "$@")"
		printf ">> checking if enabled: %s := %s\n" "$1" "$val" 1>&2
	fi
	__enabled "$@"
}

# Runs the given command under a group
_grouped() {
	local name="$1"; shift
	printf '::group::%s\n' "$name"
	"$@"
	printf '::endgroup::\n'
}

# Wrapper to run a system-altering command.
# This will always print the command.
_command() {
	printf "%s" "$PS4"
	printf "%q " "$@"
	if __enabled "dry-run"; then
		printf " # (dry-run, not running)"
		printf "\n"
		return 0
	fi
	printf "\n"
	"${@}"
}

_indent() {
	"$@" | sed -e 's/^/    /'
}

_lsblk() {
	lsblk --raw --noheadings "$@"
}

_disks_physical() {
	(
		shopt -s nullglob
		echo /dev/nvme?n? /dev/hd? /dev/sd? /dev/vd?
	)
}

_disks_without_mounts() {
	for d in "$@"; do
		if ! (_lsblk --output MOUNTPOINT "$d" | grep '^/' > /dev/null); then
			echo "$d"
		fi
	done
}

_disks_with_media() {
	for d in "$@"; do
		if (_lsblk --nodeps --output SIZE "$d" | grep -v '0B' > /dev/null); then
			echo "$d"
		fi
	done
}

_lsswap() {
	swapon --show=NAME,TYPE --raw --noheadings | grep '\b'"$1"'$' | cut -d' ' -f1
}

_swapfile_mountpoint() {
	stat -c %m -- "$1"
}

_free_space() {
	df --sync --block-size=1 --output=avail "$1" | tail -n1
}

_read_project_config_without_comments() {
	local path="$1"; shift
	< "${MORE_SPACE_ACTION_TOP}/${path}" sed -e 's/#.*//g' | grep -v '^\s*$'
}

MAIN_MOUNTPOINTS=( / /mnt )
_system_stats() {
	(
		(
			echo "NOTE: initial space usage:"
			set -x
			(
				df -h "${MAIN_MOUNTPOINTS[@]}"
			) | tee more-space.initial.df.txt
		) 2>&1
		(
			(
				set -x
				df -h

				# shellcheck disable=SC2046
				df -h $(findmnt --real --raw --noheadings --output TARGET)

				findmnt --real
				lsblk
				swapon

				uname -a
				cat /etc/lsb-release
				cat /etc/os-release
			)
			echo ""
			echo "Physical disks"
			_indent _disks_physical
			echo "Disks without mounts"
			# shellcheck disable=SC2046
			_indent _disks_without_mounts $(_disks_physical)
			echo "Disks with media"
			# shellcheck disable=SC2046
			_indent _disks_with_media $(_disks_physical)
			echo "Disks not mounted, with media"
			# shellcheck disable=SC2046
			_indent _disks_with_media $(_disks_without_mounts $(_disks_physical))
			echo "All swap"
			_indent _lsswap
			echo "Swap files"
			_indent _lsswap file
			echo "Swap partitions"
			_indent _lsswap partition
		) 2>&1 | tee more-space.system-stats.txt
	)
}

_final_system_stats() {
	(
		echo "Before:"
		_indent cat more-space.initial.df.txt
		echo "After:"
		_indent df -h "${MAIN_MOUNTPOINTS[@]}"
	) | tee more-space.final-stats.txt
}

declare -A MORE_SPACE_ACTION_TITLES
MORE_SPACE_ACTIONS=()

_register_action() {
	local title="$1"; shift
	local name="$1"; shift
	MORE_SPACE_ACTIONS+=( "$name" )
	MORE_SPACE_ACTION_TITLES+=( ["$name"]="$title" )
}

# To be ran under `_grouped`...
_run_action_actual() {
	"$@"
	echo ""
	echo "********************************************************************************"
	echo "Free space after ${action}:"
	_indent df -h "${MAIN_MOUNTPOINTS[@]}"
	echo "********************************************************************************"
}
_run_action() {
	local action="$1"; shift
	_grouped "${MORE_SPACE_ACTION_TITLES["$action"]}" _run_action_actual "$action"
}

#
# Actions
#

# NOTE: this needs to happen before the apt prune fest.
docker-prune-all() {
	_command docker system prune --all --volumes --force
}
_register_action "Pruning docker content" "docker-prune-all"

remove-apt-patterns() {
	(
		if _enabled "enable-remove-default-apt-patterns" "true"; then
			_read_project_config_without_comments "defaults/apt-patterns.list"
		fi
		printf "%s\n" "$(_get_input "additional-apt-patterns" "")"
	) | grep -v '^\s*$' | while read -r -a p; do
		# One pattern at a time so a failure isn't critical...
		_command apt autopurge "${p[@]}"
	done
	_command apt clean
}
_register_action "Removing apt packages from pattern" "remove-apt-patterns"

remove-non-package-usr() {
	for p in /usr/share/*; do
		if ! dpkg -S "$p" > /dev/null 2>&1; then
			_command rm -rf "$p"
		fi
	done
}
_register_action "Removing /usr/ files not owned by packages" "remove-non-package-usr"

remove-space-hogs() {
	(
		if _enabled "enable-remove-default-space-hogs" "true"; then
			_read_project_config_without_comments "defaults/space-hogs.list"
		fi
		printf "%s\n" "$(_get_input "additional-space-hogs" "")"
	) | grep -v '^\s*$' | while read -r -a p; do
		_command rm -rf "${p[@]}"
	done
}
_register_action "Removing space hogs by path" "remove-space-hogs"

remove-home-folder-hogs() {
	for home in /home/*; do
		(
			if _enabled "enable-remove-default-home-folder-hogs" "true"; then
				_read_project_config_without_comments "defaults/home-folder-hogs.list"
			fi
			printf "%s\n" "$(_get_input "additional-home-folder-hogs" "")"
		) | grep -v '^\s*$' | while read -r -a dirs; do
			for dir in "${dirs[@]}"; do
				_command rm -rf "$home/${dir}"
			done
		done
	done
}
_register_action "Removing home-folder hogs by path" "remove-home-folder-hogs"

remove-usr-local() {
	echo "This one takes a while..."
	_command rm -rf /usr/local/
}
_register_action "Removing /usr/local" "remove-usr-local"

second-drive-harmonization() {
	local drive
	echo ""
	echo "Swap before:"
	_indent swapon
	echo ""
	echo "=> Harmonizing /mnt"
	if ! findmnt --mountpoint /mnt > /dev/null; then
		echo "   Creating and mounting /mnt"
		# shellcheck disable=SC2046
		drive=$(_disks_with_media $(_disks_without_mounts $(_disks_physical)) | head -n1)
		if [[ "${drive}" != "" ]]; then
			# Not typical, but we *can* just create an fs on a block device!
			_command mkfs.ext4 "$drive"
			_command mkdir -p /mnt
			_command mount "$drive" "/mnt"
		else
			(
				echo "::warning::No second drive found for this system configuration..."
			) 1>&2
		fi
	else
		echo "   The /mnt mountpoint already exists"
	fi

	if _enabled "enable-swapfile"; then
		echo ""
		echo "=> Re-creating swapfile"
		for swapfile in $(_indent _lsswap file); do
			_command swapoff "$swapfile"
			_command rm -f "$swapfile"
		done
		_command fallocate --length "$(_get_input "swapfile-size")" "$(_get_input "swapfile-location")"
		_command chmod 600 "$(_get_input "swapfile-location")"
		_command mkswap "$(_get_input "swapfile-location")"
		_command swapon "$(_get_input "swapfile-location")"
		echo ""
	fi

	echo "Swap after:"
	_indent swapon
	echo ""
}
_register_action "Second drive harmonization" "second-drive-harmonization"


lvm-span() {
	local length=1G
	local -a MOUNTPOINTS
	local -a SPAN_LOOP
	local freespace_data
	freespace_data=$(_get_input "lvm-span-free-space" "{}")

	# NOTE: dashes in VG names will be escaped by doubling them.
	local vg="lvm_span"

	if ! (
		set -eu

		# shellcheck disable=2207
		MOUNTPOINTS=( $(_get_input "lvm-span-mountpoints" "") )

		for mountpoint in "${MOUNTPOINTS[@]}"; do
			local span_file="$mountpoint/_span.img"
			local free
			free=$( printf "%s" "$freespace_data" | jq --raw-output '.[$mp] // ""' --arg mp "$mountpoint" )
			if [[ "$free" == "" ]]; then
				free=$(_get_input "lvm-span-default-free-space" "$(( 100 * 1024 * 1024 ))")
			fi
			free=$(( free ))
			disk_free=$(_free_space "$mountpoint")
			length=$(( disk_free - free ))
			_command fallocate --length "$length" "$span_file"
			_command ls -lh "$span_file"
			local loopdev
			loopdev=$(
				if ! __enabled "dry-run"; then
					losetup --find --show "$span_file"
				else
					echo "/dev/dry-run/${span_file}"
				fi
			)
			_command pvcreate "$loopdev"
			SPAN_LOOP+=( "$loopdev" )
		done

		_command vgcreate "$vg" "${SPAN_LOOP[@]}"
		_command lvcreate --extents 100%FREE --name "main" "$vg"
		# -m 0 → reserved-blocks-percentage
		# -E nodiscard → Do not attempt to discard blocks at mkfs time.
		#                (Otherwise the sparse file gets discarded, and free space becomes
		#                 overprovisioned between the volume and real filesystems...)
		_command mkfs.ext4 -E nodiscard -m 0 "/dev/mapper/$vg-main"
		_command mkdir -p "$(_get_input "lvm-span-mountpoint" "")"
		_command mount "/dev/mapper/$vg-main" "$(_get_input "lvm-span-mountpoint" "")"
	); then
		printf '::error title=%s::%s' \
			"Failed to create LVM span" \
			"The LVM span could not be created."
		exit 1
	fi
	MAIN_MOUNTPOINTS+=( "$(_get_input "lvm-span-mountpoint" "")" )
}
_register_action "Second drive harmonization" "lvm-span"

#
# Main script
#

main() {
	_grouped "Gathering system statistics..." _system_stats

	echo ""
	echo " ✨ ✨ About to run system altering commands... ✨ ✨"
	echo ""

	for action in "${MORE_SPACE_ACTIONS[@]}"; do
		if _enabled "enable-${action}" "true"; then
			_run_action "$action"
		else
			printf '\nNOTE: Skipping %q, it is not enabled...\n\n' "$action"
		fi
	done

	echo ""
	_grouped "Gathering final system statistics..." _final_system_stats

	# We're done!
	echo ""
	echo " ✨ ✨ The more space action ran to the end. ✨ ✨"
	echo ""
}

main "$@"
