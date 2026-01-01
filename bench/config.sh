#!/usr/bin/env bash
# bench/config.sh - Benchmark configuration
# Adjust these variables to match your environment

#------------------------------------------------------------------------------
# Tool paths
#------------------------------------------------------------------------------
# mygrep binary path (built from this repository)
# Default assumes `go build -o bin/mygrep ./cmd/grep`
MYGREP_BIN="${MYGREP_BIN:-./bin/mygrep}"

# ripgrep (rg) binary - usually installed system-wide
RG_BIN="${RG_BIN:-rg}"

# GNU grep binary
# On macOS with Homebrew: /opt/homebrew/bin/ggrep or /usr/local/bin/ggrep
# On Linux: /usr/bin/grep or /bin/grep
if [[ "$(uname)" == "Darwin" ]]; then
    GREP_BIN="${GREP_BIN:-ggrep}"
else
    GREP_BIN="${GREP_BIN:-grep}"
fi

#------------------------------------------------------------------------------
# mygrep CLI options
#------------------------------------------------------------------------------
# Recursive flag for mygrep (empty if not supported or not needed)
# Current implementation only supports single file, so this is empty
MYGREP_RECURSIVE_FLAG=""

# Additional flags for mygrep (if any)
MYGREP_EXTRA_FLAGS=""

#------------------------------------------------------------------------------
# Hyperfine settings
#------------------------------------------------------------------------------
# Number of warmup runs before actual measurement
WARMUP_RUNS=3

# Number of measurement runs
BENCH_RUNS=10

# Minimum number of runs (hyperfine will run at least this many)
MIN_RUNS=5

#------------------------------------------------------------------------------
# Corpus settings
#------------------------------------------------------------------------------
# Directory for generated corpus data
CORPUS_DIR="./bench/corpus"

# Code tree corpus (type A) settings
CODE_TREE_NUM_FILES=1000
CODE_TREE_AVG_LINES=100

# Large log file corpus (type B) settings
LOG_FILE_NUM_LINES=1000000
LOG_FILE_LINE_LENGTH=120

# Binary corpus (type C) settings
BINARY_FILE_SIZE_MB=50

#------------------------------------------------------------------------------
# Search patterns (fixed strings only, no regex)
#------------------------------------------------------------------------------
# Common pattern for benchmarking (should exist in corpus)
SEARCH_PATTERN_COMMON="TODO"

# Rare pattern (few matches)
SEARCH_PATTERN_RARE="XYZZY_UNLIKELY_PATTERN"

# Pattern that appears frequently
SEARCH_PATTERN_FREQUENT="the"

#------------------------------------------------------------------------------
# Output settings
#------------------------------------------------------------------------------
# Results directory
RESULTS_DIR="./bench/results"

# Date format for result file names
DATE_FORMAT="%Y%m%d_%H%M%S"

#------------------------------------------------------------------------------
# Cold run settings (cache clearing)
#------------------------------------------------------------------------------
# Command to clear page cache (requires sudo on Linux)
# On Linux: sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
# On macOS: sudo purge
if [[ "$(uname)" == "Darwin" ]]; then
    CLEAR_CACHE_CMD="sudo purge"
else
    CLEAR_CACHE_CMD="sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null"
fi
