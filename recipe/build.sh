#!/usr/bin/env bash

set -e
set -x

if [[ "$c_compiler" == "gcc" ]]; then
  export PATH="${PATH}:${BUILD_PREFIX}/${HOST}/sysroot/usr/lib"
fi

export PYTHON=
export LDFLAGS="$LDFLAGS -L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export CFLAGS="$CFLAGS -fPIC -I$PREFIX/include"
#export LD_LIBRARY_PATH="/lib64:$LD_LIBRARY_PATH"



mkdir ../build && cd ../build

# A few tests are currently failing - these appear to be issues with the code rather than with the
# build process. We generate a list of tests to pass to ctest by skipping the failing ones.
# This should be removed once the tests are fixed internally at ECMWF.
if [[ $(uname) == Linux ]]; then
    # 25: inline_c.mv_dummy_target (not surprising and not important for 99% of people)
    # 40: thermo.mv_dummy_target (fixed in Metview 5.7.0)
    export TESTS_TO_SKIP="25,40"
elif [[ $(uname) == Darwin ]]; then
    # 25: inline_c.mv_dummy_target (not surprising and not important for 99% of people)
    # 34: fieldsets.mv_dummy_target (sort() - to be fixed)
    # 40: thermo.mv_dummy_target (fixed in Metview 5.7.0)
    export TESTS_TO_SKIP="25,34,40"
fi
NUM_TESTS=47 python $RECIPE_DIR/gen_test_list.py

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
    RPCGEN_PATH_FLAGS="-DRPCGEN_PATH=/usr/bin"
else
    RPCGEN_USE_CPP_ENV=0
fi

cmake -D CMAKE_INSTALL_PREFIX=$PREFIX \
      -D ENABLE_DOCS=0 \
      -D ENABLE_FORTRAN=OFF \
      -D ENABLE_METVIEW_FORTRAN=OFF \
      -D RPCGEN_USE_CPP_ENV=$RPCGEN_USE_CPP_ENV \
      -D ECBUILD_LOG_LEVEL=DEBUG \
      $RPCGEN_PATH_FLAGS \
      $SRC_DIR

make -j $CPU_COUNT VERBOSE=1

cd metview
echo "Ignoring the following tests:"
cat test_list.txt
ctest --output-on-failure -j $CPU_COUNT -I test_list.txt
make install
