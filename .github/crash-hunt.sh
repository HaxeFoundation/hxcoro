#!/usr/bin/env bash
# Temporary: loops the cpp test binaries to catch the intermittent crash at process exit
# (HaxeFoundation/hxcoro#219) and prints all-thread backtraces from the core dump.
# Usage: crash-hunt.sh <seconds> <binary>...
set -u

duration=$1
shift
binaries=("$@")

ulimit -c unlimited
cores=/tmp/cores
mkdir -p "$cores"

end=$((SECONDS + duration))
runs=0
crashes=0
i=0
while [ $SECONDS -lt $end ] && [ $crashes -lt 3 ]; do
	bin=${binaries[$((i % ${#binaries[@]}))]}
	# Every other pass over the binaries, fill freed and allocated memory with a pattern so
	# that heap misuse shows up sooner.
	if [ $(((i / ${#binaries[@]}) % 2)) -eq 1 ]; then
		tunables=glibc.malloc.perturb=165
	else
		tunables=
	fi
	i=$((i + 1))
	rm -f "$cores"/core.*
	GLIBC_TUNABLES=$tunables "$bin" > /tmp/run.out 2>&1
	code=$?
	runs=$((runs + 1))
	if [ $code -ne 0 ]; then
		crashes=$((crashes + 1))
		echo "::group::Crash $crashes: $bin exited with $code on run $runs (GLIBC_TUNABLES=$tunables)"
		grep -a -v ' \.\.\. OK$' /tmp/run.out | tail -30
		core=$(ls "$cores"/core.* 2>/dev/null | head -1)
		if [ -n "$core" ]; then
			gdb -q -batch -ex "set pagination off" -ex "info threads" -ex "thread apply all bt 50" "$bin" "$core" 2>&1 | grep -v "^\[New LWP"
		else
			echo "No core dump found"
		fi
		echo "::endgroup::"
		echo "::error::Crash $crashes: $bin exited with $code on run $runs"
	fi
done
echo "$runs runs, $crashes crashes"
[ $crashes -eq 0 ]
