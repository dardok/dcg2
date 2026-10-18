#!/usr/bin/env bash

case ${CATEGORY}/${PN} in
    app-portage/eix)
        export EXTRA_ECONF="--enable-security --enable-new-dialect --enable-strong-optimization"
        ;;
    dev-libs/cutlass)
        export CMAKE_CUDA_HOST_COMPILER="/usr/*linux-gnu/gcc-bin/16*"
        ;;
    *)
        ;;
esac
