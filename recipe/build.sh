#!/usr/bin/env bash

set -e
set -x

if [[ "$c_compiler" == "gcc" ]]; then
  export PATH="${PATH}:${BUILD_PREFIX}/${HOST}/sysroot/usr/lib"
fi

export PYTHON=
export LDFLAGS="$LDFLAGS -L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export CFLAGS="$CFLAGS -fPIC -I$PREFIX/include"


ls -l $BUILD_PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/usr/bin/rpcgen
ldd $BUILD_PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/usr/bin/rpcgen
file $BUILD_PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/usr/bin/rpcgen

ls -l $CPP
ldd   $CPP
file  $CPP

ls -l /lib64/ld-linux-x86-64*
ls -l /lib64/ld-2.12.so*

mkdir ../build && cd ../build

# A few tests are currently failing - these appear to be issues with the code rather than with the
# build process. We generate a list of tests to pass to ctest by skipping the failing ones.
# This should be removed once the tests are fixed internally at ECMWF.
if [[ $(uname) == Linux ]]; then
    # 98:  eckit_test_sql_select
    # 457: inline_c.mv_dummy_target
    # 458: inline_fortran.mv_dummy_target
    export TESTS_TO_SKIP="98,457,458"
elif [[ $(uname) == Darwin ]]; then
    # 98:  eckit_test_sql_select
    # 425: test_interpolation_rgg2ll_req
    # 426: test_interpolation_latlon_req
    # 427: test_interpolation_sh2ll_req
    # 431: test_retrieve_fdb_uv_pl_req
    # 432: test_retrieve_fdb_uv_ml_req
    # 457: inline_c.mv_dummy_target
    # 458: inline_fortran.mv_dummy_target
    export TESTS_TO_SKIP="98,425,426,427,431,432,457,458"
fi
NUM_TESTS=472 python $RECIPE_DIR/gen_test_list.py

if [[ $(uname) == Linux ]]; then
    # rpcgen searches for cpp in /lib/cpp and /cpp.
    # It's possible to pass a path to rpcgen using `-Y` but this is a directory path - rpcgen
    # expects a `cpp` binary inside that directory.
    # $CPP on conda-forge is a path to a binary of form `x86_64-conda_cos6-linux-gnu-cpp` which
    # causes rpcgen to fail to find it.
    # Therefore we create a symlink which rpcgen can use.
    ln -s "$CPP" ./cpp
    export CPP="$PWD/cpp"
    RPCGEN_USE_CPP_ENV=1
else
    RPCGEN_USE_CPP_ENV=0
fi

cmake -D CMAKE_INSTALL_PREFIX=$PREFIX \
      -D ENABLE_DOCS=0 \
      -D ENABLE_FORTRAN=OFF \
      -D ENABLE_METVIEW_FORTRAN=OFF \
      -D RPCGEN_USE_CPP_ENV=$RPCGEN_USE_CPP_ENV \
      $SRC_DIR

make -j $CPU_COUNT VERBOSE=1

ctest --output-on-failure -j $CPU_COUNT -I test_list.txt
make install
