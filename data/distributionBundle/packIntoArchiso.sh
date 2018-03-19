#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# region header
# Copyright Torben Sickert (info["~at~"]torben.website) 16.12.2012

# License
# -------

# This library written by Torben Sickert stand under a creative commons naming
# 3.0 unported license. see http://creativecommons.org/licenses/by/3.0/deed.de
# endregion
# shellcheck disable=SC2016,SC2034,SC2155
# region import
if [ -f "$(dirname "${BASH_SOURCE[0]}")/node_modules/bashlink/module.sh" ]; then
    # shellcheck disable=SC1090
    source "$(dirname "${BASH_SOURCE[0]}")/node_modules/bashlink/module.sh"
elif [ -f "/usr/lib/bashlink/module.sh" ]; then
    # shellcheck disable=SC1091
    source "/usr/lib/bashlink/module.sh"
else
    echo Needed bashlink library not found 1>&2
    exit 1
fi
bl.module.import bashlink.logging
bl.module.import bashlink.tools
# endregion
# region variables
packIntoArchiso__documentation__='
    This module modifies a given arch linux iso image.

    Packs the current packIntoArchiso.bash script into the archiso image.

    Remaster archiso file.

    ```bash
        pack-into-archiso ./archiso.iso ./remasteredArchiso.iso
    ```

    Remaster archiso file verbosely.

    ```bash
        pack-into-archiso ./archiso.iso ./remasteredArchiso.iso --verbose
    ```

    Show help message.

    ```bash
        pack-into-archiso --help
    ```
'
packIntoArchiso__dependencies__=(
    bash
    cdrkit
    grep
    mktemp
    mount
    readlink
    rm
    squashfs-tools
    touch
    umount
)
packIntoArchiso__optional_dependencies__=(
    'sudo: Perform action as another user.'
    'arch-install-scripts: Supports to perform an arch-chroot.'
)
## region commandline arguments
packIntoArchiso_squash_filesystem_compressor=gzip
packIntoArchiso_keyboard_layout=de-latin1
packIntoArchiso_key_map_configuration_file_content="KEYMAP=${packIntoArchiso_keyboard_layout}"$'\nFONT=Lat2-Terminus16\nFONT_MAP='
## endregion
packIntoArchiso_source_path=''
packIntoArchiso_target_path=''
packIntoArchiso_mountpoint_path="$(mktemp --directory)"
packIntoArchiso_temporary_remastering_path="$(mktemp --directory)"
packIntoArchiso_temporary_filesystem_remastering_path="$(mktemp --directory)/mnt"
packIntoArchiso_temporary_root_filesystem_remastering_path="$(mktemp --directory)"
packIntoArchiso_relative_paths_to_squash_filesystem=(
    arch/i686/root-image.fs.sfs
    arch/x86_64/root-image.fs.sfs
)
packIntoArchiso_relative_source_file_path=archInstall.sh
packIntoArchiso_relative_target_file_path=usr/bin/
packIntoArchiso_bashrc_code=$'\nalias getInstallScript='"'wget https://goo.gl/bPAqXB --output-document archInstall.sh && chmod +x archInstall.sh'"$'\nalias install='"'([ -f /root/archInstall.sh ] || getInstallScript);/root/archInstall.sh'"
# endregion
# region functions
## region command line interface
alias packIntoArchiso.print_commandline_option_description=packIntoArchiso_print_commandline_option_description
packIntoArchiso_print_commandline_option_description() {
    local __documentation__='
        Prints descriptions about each available command line option.

        >>> packIntoArchiso.print_commandline_option_description
        +bl.doctest.contains
        +bl.doctest.multiline_ellipsis
        -h --help Shows this help message.
        ...
    '
    # NOTE: "-k" and "--key-map-configuration" isn't needed in the future.
    bl.logging.cat << EOF
-h --help Shows this help message.

-v --verbose Tells you what is going on (default: "false").

-d --debug Gives you any output from all tools which are used (default: "false").

-c --squash-filesystem-compressor Defines the squash filesystem compressor. All supported compressors for "mksquashfs" are possible (default: "$packIntoArchiso_squash_filesystem_compressor").

-k --keyboard-layout Defines needed key map (default: "$packIntoArchiso_keyboard_layout").

-m --key-map-configuration FILE_CONTENT Keyboard map configuration (default: "$packIntoArchiso_key_map_configuration_file_content").
EOF
}
alias packIntoArchiso.print_help_message=packIntoArchiso_print_help_message
packIntoArchiso_print_help_message() {
    local __documentation__='
        Provides a help message for this module.

        >>> packIntoArchiso.print_help_message
        +bl.doctest.contains
        +bl.doctest.multiline_ellipsis
        ...
        Usage: pack-into-archiso /path/to/archiso/file.iso /path/to/newly/packe
        ...
    '
    bl.logging.plain $'\nUsage: pack-into-archiso /path/to/archiso/file.iso /path/to/newly/packed/archiso/file.iso [options]\n'
    bl.logging.plain "$packIntoArchiso__documentation__"
    bl.logging.plain $'\nOption descriptions:\n'
    packIntoArchiso.print_commandline_option_description "$@"
    bl.logging.plain
}
alias packIntoArchiso.commandline_interface=packIntoArchiso_commandline_interface
packIntoArchiso_commandline_interface() {
    local __documentation__='
        Provides the command line interface and interactive questions.

        >>> packIntoArchiso.commandline_interface
        +bl.doctest.contains
        +bl.doctest.multiline_ellipsis
        You have to provide source and target file path.
        ...
    '
    while true; do
        case "$1" in
            -h|--help)
                shift
                packIntoArchiso.print_help_message "$0"
                exit 0
                ;;
            -v|--verbose)
                shift
                bl.logging.set_level info
                ;;
            -d|--debug)
                shift
                bl.logging.set_command_output_on
                ;;
            -c|--squash-filesystem-compressor)
                shift
                packIntoArchiso_squash_filesystem_compressor="$1"
                shift
                ;;
            -k|--keyboard-layout)
                shift
                packIntoArchiso_keyboard_layout="$1"
                shift
                ;;
            -m|--key-map-configuation)
                shift
                packIntoArchiso_key_map_configuration_file_content="$1"
                shift
                ;;

            '')
                shift
                break
                ;;
            *)
                if [[ ! "$packIntoArchiso_source_path" ]]; then
                    packIntoArchiso_source_path="$1"
                elif [[ ! "$packIntoArchiso_target_path" ]]; then
                    packIntoArchiso_target_path="$1"
                    if [ -d "$packIntoArchiso_target_path" ]; then
                        packIntoArchiso_target_path="$(
                            readlink \
                                --canonicalize \
                                "$packIntoArchiso_target_path"
                        )/$(basename "$packIntoArchiso_source_path")"
                    fi
                else
                    bl.logging.critical \
                        "Given argument: \"$1\" is not available." '\n'
                    packIntoArchiso.print_help_message "$0"
                fi
                shift
        esac
    done
    if [[ ! "$packIntoArchiso_source_path" ]] || [[ ! "$packIntoArchiso_target_path" ]]; then
        bl.logging.critical \
            You have to provide source and target file path. $'\n'
        packIntoArchiso.print_help_message "$0"
        return 1
    fi
}
## endregion
## region helper
alias packIntoArchiso.remaster_iso=packIntoArchiso_remaster_iso
packIntoArchiso_remaster_iso() {
    local __documentation__='
        Remasters given iso into new iso. If new systemd programs are used (if
        first argument is "true") they could have problems in change root
        environment without and exclusive dbus connection.
    '
    bl.logging.info \
        "Mount \"$packIntoArchiso_source_path\" to \"$packIntoArchiso_mountpoint_path\"."
    mount \
        -t iso9660 \
        -o loop \
        "$packIntoArchiso_source_path" \
        "$packIntoArchiso_target_path"
    bl.logging.info \
        "Copy content in \"$packIntoArchiso_mountpoint_path\" to \"$packIntoArchiso_temporary_remastering_path\"."
    cp --archiv "${packIntoArchiso_mountpoint_path}/"* "$packIntoArchiso_temporary_remastering_path"
    local path
    local return_code=0
    for path in "${packIntoArchiso_relative_paths_to_squash_filesystem[@]}"; do
        bl.logging.info "Extract squash file system in \"${packIntoArchiso_temporary_remastering_path}/$path\" to \"${packIntoArchiso_temporary_remastering_path}\"."
        unsquashfs \
            -d "${packIntoArchiso_temporary_filesystem_remastering_path}" \
            "${packIntoArchiso_temporary_remastering_path}/${path}"
        rm --force "${packIntoArchiso_temporary_remastering_path}/${path}"
        bl.logging.info "Mount root file system in \"${packIntoArchiso_temporary_filesystem_remastering_path}\" to \"${packIntoArchiso_temporary_root_filesystem_remastering_path}\"."
        mount \
            "${packIntoArchiso_temporary_filesystem_remastering_path}/"* \
            "$_TEMPORARY_ROOT_FILESYSTEM_REMASTERING_PATH"
        bl.logging.info "Copy \"$(
            dirname "$(readlink --canonicalize "$0")"
        )/$packIntoArchiso_relative_source_file_path\" to \"${packIntoArchiso_temporary_root_filesystem_remastering_path}/${packIntoArchiso_relative_target_file_path}\"."
        cp \
            "$(dirname "$(readlink --canonicalize "$0")")/$_RELATIVE_SOURCE_FILE_PATH" \
            "${packIntoArchiso_temporary_root_filesystem_remastering_path}/${packIntoArchiso_relative_target_file_path}"
        bl.logging.info "Set key map to \"$packIntoArchiso_keyboard_layout\"."
        if [ "$1" = true ]; then
            arch-chroot \
                "$packIntoArchiso_temporary_root_filesystem_remastering_path" \
                localectl set-keymap "$packIntoArchiso_keyboard_layout"
            arch-chroot \
                "$packIntoArchiso_temporary_root_filesystem_remastering_path" \
                set-locale LANG=en_US.utf8
        else
            bl.logging.plain \
                "$packIntoArchiso_key_map_configuration_file_content" \
                    1>"${packIntoArchiso_temporary_root_filesystem_remastering_path}/etc/vconsole.conf"
        fi
        bl.logging.info Set root symbolic link for root user.
        local file_name
        for file_name in .bashrc .cshrc .kshrc .zshrc; do
            if [ -f "${packIntoArchiso_temporary_root_filesystem_remastering_path}/root/$file_name" ]; then
                bl.logging.plain \
                    "$packIntoArchiso_bashrc_code" \
                        1>>"${packIntoArchiso_temporary_root_filesystem_remastering_path}/root/$file_name"
            else
                bl.logging.plain \
                    "$packIntoArchiso_bashrc_code" \
                        1>"${packIntoArchiso_temporary_root_filesystem_remastering_path}/root/$file_name"
            fi
        done
        bl.logging.info "Unmount \"$packIntoArchiso_temporary_root_filesystem_remastering_path\"."
        umount "$packIntoArchiso_temporary_root_filesystem_remastering_path"
        bl.logging.info "Make new squash file system from \"${packIntoArchiso_temporary_remastering_path}\" to \"${packIntoArchiso_temporary_remastering_path}/${path}\"."
        mksquashfs \
            "${packIntoArchiso_temporary_filesystem_remastering_path}" \
            "${packIntoArchiso_temporary_remastering_path}/${path}" \
            -noappend \
            -comp \
            "$packIntoArchiso_squash_filesystem_compressor"
        rm \
            --force \
            --recursive \
            "${packIntoArchiso_temporary_filesystem_remastering_path}"
        return_code=$?
        if (( return_code != 0 )); then
            bl.logging.info "Unmount \"$packIntoArchiso_mountpoint_path\"."
            umount "$packIntoArchiso_mountpoint_path"
            return $?
        fi
    done
    local volume_id="$(
        isoinfo -i "$packIntoArchiso_source_path" -d | \
            command grep --extended-regexp 'Volume id:' | \
                command grep --extended-regexp --only-matching '[^ ]+$'
    )"
    bl.logging.info "Create new iso file from \"$packIntoArchiso_temporary_remastering_path\" in \"$packIntoArchiso_target_path\" with old detected volume id \"$volume_id\"."
    pushd "${packIntoArchiso_mountpoint_path}" && \
    genisoimage \
        -boot-info-table \
        -boot-load-size 4 \
        -eltorito-boot isolinux/isolinux.bin \
        -eltorito-catalog isolinux/boot.cat \
        -full-iso9660-filenames \
        -joliet \
        -no-emul-boot \
        -output "$packIntoArchiso_target_path" \
        -rational-rock \
        -verbose \
        --volid "$volume_id" \
        "$packIntoArchiso_temporary_remastering_path"
    popd && \
    bl.logging.info "Unmount \"$packIntoArchiso_mountpoint_path\"."
    umount "$packIntoArchiso_mountpoint_path"
}
alias packIntoArchiso.tidy_up=packIntoArchiso_tidy_up
packIntoArchiso_tidy_up() {
    local __documentation__='
        Removes temporary created files.
    '
    bl.logging.info \
        "Remove temporary created location \"$packIntoArchiso_mountpoint_path\"."
    rm \
        --force \
        --recursive \
        "$packIntoArchiso_mountpoint_path"
    bl.logging.info \
        "Remove temporary created location \"$packIntoArchiso_temporary_remastering_path\"."
    rm \
        --force \
        --recursive \
        "$packIntoArchiso_temporary_remastering_path"
    bl.logging.info \
        "Remove temporary created location \"$packIntoArchiso_temporary_filesystem_remastering_path\"."
    rm \
        --force \
        --recursive \
        "$packIntoArchiso_temporary_filesystem_remastering_path"
    bl.logging.info \
        "Remove temporary created location \"$packIntoArchiso_temporary_root_filesystem_remastering_path\"."
    rm \
        --force \
        --recursive \
        "$packIntoArchiso_temporary_root_filesystem_remastering_path"
}
## endregion
## region controller
alias packIntoArchiso.main=packIntoArchiso_main
packIntoArchiso_main() {
    local __documentation__='
        Main injected point for this module.

        >>> packIntoArchiso.main --help
        +bl.doctest.contains
        +bl.doctest.multiline_ellipsis
        ...
        Usage: pack-into-archiso /path/to/archiso/file.iso /path/to/newly/packe
        ...
    '
    packIntoArchiso.commandline_interface "$@" || \
        return $?
    # Switch user if necessary and possible.
    if [[ "$USER" != root ]] && command grep root /etc/passwd &>/dev/null; then
        sudo -u root "$0" "$@"
        return $?
    fi
    packIntoArchiso.remaster_iso || \
        bl.logging.critical Remastering given iso failed.
    packIntoArchiso.tidy_up || \
        bl.logging.critical Tidying up failed.
    bl.logging.info
        "Remastering given image \"$packIntoArchiso_source_path\" to \"$packIntoArchiso_target_path\" has successfully finished."
}
## endregion
# endregion
if bl.tools.is_main; then
    packIntoArchiso.main "$@"
fi
# region vim modline
# vim: set tabstop=4 shiftwidth=4 expandtab:
# vim: foldmethod=marker foldmarker=region,endregion:
# endregion