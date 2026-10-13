#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/build.sh
if [ -d /opt/local/lib ]; then
    LD_LIBRARY_PATH="/opt/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LD_LIBRARY_PATH
fi
fail=0
./build/basic-ir selftest
./build/asm-ir selftest
run_both() {
    src=$1
    base=$(basename "$src" .bas)
    ./build/basic-ir run "$src" "build/$base.basic.bin"
    ./build/asm-ir run "$src" "build/$base.asm.bin"
    cmp "build/$base.basic.bin" "build/$base.asm.bin"
    echo "match $base"
}
run_both fixtures/programs/sample.bas
run_both fixtures/programs/mem.bas
if ./build/basic-ir run fixtures/programs/bad.bas build/bad.basic.bin; then
    echo "basic accepted an unknown opcode"
    fail=1
fi
if ./build/asm-ir run fixtures/programs/bad.bas build/bad.asm.bin; then
    echo "asm accepted an unknown opcode"
    fail=1
fi
./build/basic-ir verify build/sample.basic.bin
./build/asm-ir verify build/sample.asm.bin
if [ "$fail" -ne 0 ]; then
    exit 1
fi
echo "all checks passed"
