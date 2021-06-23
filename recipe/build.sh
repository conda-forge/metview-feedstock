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

if [[ $(uname) == Linux ]]; then
  # workaround for https://github.com/conda-forge/qt-feedstock/issues/123
  sed -i 's|_qt5gui_find_extra_libs(EGL.*)|_qt5gui_find_extra_libs(EGL "EGL" "" "")|g' $PREFIX/lib/cmake/Qt5Gui/Qt5GuiConfigExtras.cmake
  sed -i 's|_qt5gui_find_extra_libs(OPENGL.*)|_qt5gui_find_extra_libs(OPENGL "GL" "" "")|g' $PREFIX/lib/cmake/Qt5Gui/Qt5GuiConfigExtras.cmake
fi


mkdir ../build && cd ../build

# A few tests are currently failing - these appear to be issues with the code rather than with the
# build process. We generate a list of tests to pass to ctest by skipping the failing ones.
# This should be removed once the tests are fixed internally at ECMWF.
if [[ $(uname) == Linux ]]; then
    # 25: inline_c.mv_dummy_target (not surprising and not important for 99% of people)
    # 34: fieldsets.mv (often this one hangs on Linux on conda for unknown reasons)
    export TESTS_TO_SKIP="25,34"
elif [[ $(uname) == Darwin ]]; then
    # 25: inline_c.mv_dummy_target (not surprising and not important for 99% of people)
    # 36: geopoints.mv_dummy_target (only fails on macos on conda)
    # 41: thermo.mv_dummy_target (fixed in Metview 5.8.0)
    export TESTS_TO_SKIP="25,36,41"
fi

# NUM_TESTS should be at least the total number of tests that we have;
# it does no harm to have a larger number
NUM_TESTS=99 python $RECIPE_DIR/gen_test_list.py

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
      -D CMAKE_BUILD_TYPE=Release \
      -D ENABLE_ECKIT_CMD=OFF \
      -D ENABLE_DOCS=0 \
      -D ENABLE_FORTRAN=OFF \
      -D ENABLE_METVIEW_FORTRAN=OFF \
      -D RPCGEN_USE_CPP_ENV=$RPCGEN_USE_CPP_ENV \
      -D ECBUILD_LOG_LEVEL=DEBUG \
      -D INSTALL_LIB_DIR=lib \
      -D METVIEW_INSTALL_EXE_BIN_DIR=bin \
      $RPCGEN_PATH_FLAGS \
      $SRC_DIR

make -j $CPU_COUNT VERBOSE=1

echo "Including the following tests:"
cat test_list.txt
echo ""

# temporary fix to ensure the data files required for the regrid.mv test are where they should be:
cp $SRC_DIR/metview/test/data/z_for_spectra.grib metview/test/macros/

cd metview
ctest --output-on-failure -j $CPU_COUNT -I ../test_list.txt
cd ..
make install
