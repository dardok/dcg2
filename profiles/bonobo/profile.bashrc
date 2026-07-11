#!/usr/bin/env bash

case ${CATEGORY}/${PN} in
    sys-apps/busybox)
        # see https://bugs.gentoo.org/454294#c7
        ;;
    app-emulation/libguestfs)
        # ACCESS DENIED:  open_wr: /dev/sgx_vepc when testing qemu
        export FEATURES="-sandbox -usersandbox"
        ;;
    *)
        export KBUILD_OUTPUT="/usr/src/linux-obj"
        ;;
esac
