#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
if [ -x /opt/local/bin/fbc ]; then
    PATH="/opt/local/bin:$PATH"
    export PATH
fi
if [ -d /opt/local/lib ]; then
    LD_LIBRARY_PATH="/opt/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LD_LIBRARY_PATH
fi
command -v fbc >/dev/null
command -v nasm >/dev/null
command -v ld >/dev/null
fbc -gen gcc -w all -x build/basic-ir basic/ir.bas
nasm -f elf64 -w+all -I asm -o build/asm-ir.o asm/runtime.asm
ld -o build/asm-ir build/asm-ir.o
echo "built build/basic-ir and build/asm-ir"
