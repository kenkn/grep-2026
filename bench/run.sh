#!/usr/bin/env bash
# bench/run.sh - Main benchmark runner
# Usage: ./bench/run.sh [OPTIONS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

#------------------------------------------------------------------------------
# Global variables
#------------------------------------------------------------------------------
TIMESTAMP=$(date +"${DATE_FORMAT}")
RUN_COLD=false
CORPUS_TYPE="all"
PATTERN_TYPE="common"
VERBOSE=false
DRY_RUN=false
SKIP_BINARY_CHECK=false

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_verbose() {
    if [[ "${VERBOSE}" == true ]]; then
        echo "[DEBUG] $*"
    fi
}

check_command() {
    local cmd="$1"
    local name="$2"
    if ! command -v "${cmd}" &> /dev/null; then
        return 1
    fi
    return 0
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing=()

    # Check hyperfine
    if ! check_command "hyperfine" "hyperfine"; then
        missing+=("hyperfine")
    fi

    # Check mygrep
    if [[ ! -x "${MYGREP_BIN}" ]]; then
        log_error "mygrep binary not found at: ${MYGREP_BIN}"
        log_error ""
        log_error "Please build mygrep first:"
        log_error "  cd $(pwd)"
        log_error "  go build -o bin/mygrep ./cmd/grep"
        log_error ""
        log_error "Or set MYGREP_BIN environment variable to the correct path."
        exit 1
    fi

    # Check ripgrep (optional but recommended)
    if ! check_command "${RG_BIN}" "ripgrep"; then
        log_warn "ripgrep (rg) not found. Install with: brew install ripgrep (macOS) or apt install ripgrep (Linux)"
        RG_AVAILABLE=false
    else
        RG_AVAILABLE=true
    fi

    # Check GNU grep
    if ! check_command "${GREP_BIN}" "GNU grep"; then
        log_warn "GNU grep not found at ${GREP_BIN}."
        if [[ "$(uname)" == "Darwin" ]]; then
            log_warn "Install with: brew install grep"
            log_warn "Then it will be available as 'ggrep'"
        fi
        GREP_AVAILABLE=false
    else
        GREP_AVAILABLE=true
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_error "Please install them and try again."
        exit 1
    fi

    log_info "Prerequisites check passed"
    log_verbose "  mygrep: ${MYGREP_BIN}"
    log_verbose "  ripgrep: ${RG_AVAILABLE} (${RG_BIN})"
    log_verbose "  GNU grep: ${GREP_AVAILABLE} (${GREP_BIN})"
}

check_corpus() {
    local corpus_type="$1"

    case "${corpus_type}" in
        code)
            if [[ ! -d "${CORPUS_DIR}/code_tree" ]]; then
                log_error "Code tree corpus not found. Generate it with:"
                log_error "  ./bench/gen_corpus.sh --code"
                return 1
            fi
            ;;
        log)
            if [[ ! -f "${CORPUS_DIR}/log/access.log" ]]; then
                log_error "Log file corpus not found. Generate it with:"
                log_error "  ./bench/gen_corpus.sh --log"
                return 1
            fi
            ;;
        binary)
            if [[ ! -f "${CORPUS_DIR}/binary/random.bin" ]]; then
                log_error "Binary corpus not found. Generate it with:"
                log_error "  ./bench/gen_corpus.sh --binary"
                return 1
            fi
            ;;
        all)
            local all_ok=true
            for ct in code log binary; do
                if ! check_corpus "${ct}"; then
                    all_ok=false
                fi
            done
            if [[ "${all_ok}" == false ]]; then
                log_error ""
                log_error "Generate all corpus types with:"
                log_error "  ./bench/gen_corpus.sh --all"
                return 1
            fi
            ;;
    esac
    return 0
}

get_search_pattern() {
    local pattern_type="$1"
    case "${pattern_type}" in
        common)   echo "${SEARCH_PATTERN_COMMON}" ;;
        rare)     echo "${SEARCH_PATTERN_RARE}" ;;
        frequent) echo "${SEARCH_PATTERN_FREQUENT}" ;;
        *)        echo "${pattern_type}" ;;  # Allow custom patterns
    esac
}

clear_cache() {
    if [[ "${RUN_COLD}" == true ]]; then
        log_verbose "Clearing page cache..."
        eval "${CLEAR_CACHE_CMD}" 2>/dev/null || {
            log_warn "Failed to clear cache. Cold benchmarks may not be accurate."
            log_warn "Try running with sudo or skip cold benchmarks."
        }
    fi
}

get_file_size_mb() {
    local path="$1"
    if [[ -d "${path}" ]]; then
        du -sm "${path}" | cut -f1
    else
        du -sm "${path}" | cut -f1
    fi
}

#------------------------------------------------------------------------------
# Benchmark functions
#------------------------------------------------------------------------------

run_benchmark_single_file() {
    local name="$1"
    local file="$2"
    local pattern="$3"
    local output_file="$4"

    log_info "Running benchmark: ${name}"
    log_info "  File: ${file}"
    log_info "  Pattern: '${pattern}'"
    log_info "  Output: ${output_file}"

    local size_mb
    size_mb=$(get_file_size_mb "${file}")
    log_verbose "  File size: ${size_mb} MB"

    # Build commands
    # All tools: fixed-string search, output to /dev/null for fair comparison
    local cmd_mygrep="${MYGREP_BIN} '${pattern}' '${file}' > /dev/null"
    local cmd_rg="${RG_BIN} --fixed-strings --no-filename '${pattern}' '${file}' > /dev/null"
    local cmd_grep="${GREP_BIN} --fixed-strings '${pattern}' '${file}' > /dev/null"

    # Build hyperfine command
    local hyperfine_opts=(
        "--warmup" "${WARMUP_RUNS}"
        "--runs" "${BENCH_RUNS}"
        "--export-json" "${output_file}"
        "--style" "full"
    )

    # Add prepare command for cold runs
    if [[ "${RUN_COLD}" == true ]]; then
        hyperfine_opts+=("--prepare" "${CLEAR_CACHE_CMD}")
    fi

    # Build the command list
    local commands=()
    commands+=("--command-name" "mygrep" "${cmd_mygrep}")

    if [[ "${RG_AVAILABLE}" == true ]]; then
        commands+=("--command-name" "ripgrep" "${cmd_rg}")
    fi

    if [[ "${GREP_AVAILABLE}" == true ]]; then
        commands+=("--command-name" "gnu-grep" "${cmd_grep}")
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "DRY RUN - would execute:"
        echo "  hyperfine ${hyperfine_opts[*]} ${commands[*]}"
        return
    fi

    # Run hyperfine
    hyperfine "${hyperfine_opts[@]}" "${commands[@]}" || {
        log_warn "Benchmark failed or was interrupted"
        return 1
    }

    # Add metadata to JSON result
    add_metadata_to_result "${output_file}" "${name}" "${pattern}" "${size_mb}" "${file}"
}

run_benchmark_directory() {
    local name="$1"
    local dir="$2"
    local pattern="$3"
    local output_file="$4"

    log_info "Running benchmark: ${name}"
    log_info "  Directory: ${dir}"
    log_info "  Pattern: '${pattern}'"
    log_info "  Output: ${output_file}"

    local size_mb
    size_mb=$(get_file_size_mb "${dir}")
    local file_count
    file_count=$(find "${dir}" -type f | wc -l | tr -d ' ')
    log_verbose "  Size: ${size_mb} MB, Files: ${file_count}"

    # Build commands for directory search
    # mygrep: Need to iterate through files (since current impl is single-file only)
    # Using find + xargs for mygrep as a workaround
    local cmd_mygrep="find '${dir}' -type f -exec ${MYGREP_BIN} '${pattern}' {} \\; > /dev/null 2>&1"

    # ripgrep: native recursive search with fixed-string
    local cmd_rg="${RG_BIN} --fixed-strings '${pattern}' '${dir}' > /dev/null"

    # GNU grep: recursive with fixed-string
    local cmd_grep="${GREP_BIN} --fixed-strings --recursive '${pattern}' '${dir}' > /dev/null"

    # Build hyperfine command
    local hyperfine_opts=(
        "--warmup" "${WARMUP_RUNS}"
        "--runs" "${BENCH_RUNS}"
        "--export-json" "${output_file}"
        "--style" "full"
        "--shell" "bash"
    )

    if [[ "${RUN_COLD}" == true ]]; then
        hyperfine_opts+=("--prepare" "${CLEAR_CACHE_CMD}")
    fi

    local commands=()
    commands+=("--command-name" "mygrep" "${cmd_mygrep}")

    if [[ "${RG_AVAILABLE}" == true ]]; then
        commands+=("--command-name" "ripgrep" "${cmd_rg}")
    fi

    if [[ "${GREP_AVAILABLE}" == true ]]; then
        commands+=("--command-name" "gnu-grep" "${cmd_grep}")
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "DRY RUN - would execute:"
        echo "  hyperfine ${hyperfine_opts[*]} ${commands[*]}"
        return
    fi

    hyperfine "${hyperfine_opts[@]}" "${commands[@]}" || {
        log_warn "Benchmark failed or was interrupted"
        return 1
    }

    add_metadata_to_result "${output_file}" "${name}" "${pattern}" "${size_mb}" "${dir}" "${file_count}"
}

add_metadata_to_result() {
    local output_file="$1"
    local bench_name="$2"
    local pattern="$3"
    local size_mb="$4"
    local target_path="$5"
    local file_count="${6:-1}"

    if [[ ! -f "${output_file}" ]]; then
        return
    fi

    # Convert shell boolean to Python boolean
    local cold_run_py="False"
    if [[ "${RUN_COLD}" == "true" ]]; then
        cold_run_py="True"
    fi

    # Add metadata using Python (more reliable JSON handling)
    python3 << EOF
import json
import sys

try:
    with open("${output_file}", "r") as f:
        data = json.load(f)

    data["metadata"] = {
        "benchmark_name": "${bench_name}",
        "pattern": "${pattern}",
        "target_path": "${target_path}",
        "size_mb": ${size_mb},
        "file_count": ${file_count},
        "timestamp": "${TIMESTAMP}",
        "cold_run": ${cold_run_py},
        "warmup_runs": ${WARMUP_RUNS},
        "bench_runs": ${BENCH_RUNS}
    }

    with open("${output_file}", "w") as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f"Warning: Failed to add metadata: {e}", file=sys.stderr)
EOF
}

#------------------------------------------------------------------------------
# Main benchmark suites
#------------------------------------------------------------------------------

run_code_tree_benchmark() {
    local pattern
    pattern=$(get_search_pattern "${PATTERN_TYPE}")
    local cache_mode
    if [[ "${RUN_COLD}" == true ]]; then cache_mode="cold"; else cache_mode="warm"; fi

    local output_file="${RESULTS_DIR}/code_tree_${PATTERN_TYPE}_${cache_mode}_${TIMESTAMP}.json"

    run_benchmark_directory "code_tree_${PATTERN_TYPE}" \
        "${CORPUS_DIR}/code_tree" \
        "${pattern}" \
        "${output_file}"
}

run_log_file_benchmark() {
    local pattern
    pattern=$(get_search_pattern "${PATTERN_TYPE}")
    local cache_mode
    if [[ "${RUN_COLD}" == true ]]; then cache_mode="cold"; else cache_mode="warm"; fi

    local output_file="${RESULTS_DIR}/log_file_${PATTERN_TYPE}_${cache_mode}_${TIMESTAMP}.json"

    run_benchmark_single_file "log_file_${PATTERN_TYPE}" \
        "${CORPUS_DIR}/log/access.log" \
        "${pattern}" \
        "${output_file}"
}

run_binary_file_benchmark() {
    if [[ "${SKIP_BINARY_CHECK}" == true ]]; then
        log_warn "Skipping binary benchmark (binary files may cause issues with some tools)"
        return
    fi

    local pattern="EMBEDDED_STRING"
    local cache_mode
    if [[ "${RUN_COLD}" == true ]]; then cache_mode="cold"; else cache_mode="warm"; fi

    local output_file="${RESULTS_DIR}/binary_file_${cache_mode}_${TIMESTAMP}.json"

    log_info "Running binary file benchmark"
    log_info "  Note: This tests how tools handle binary files"

    run_benchmark_single_file "binary_file" \
        "${CORPUS_DIR}/binary/random.bin" \
        "${pattern}" \
        "${output_file}"
}

#------------------------------------------------------------------------------
# CLI interface
#------------------------------------------------------------------------------

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Run grep benchmarks comparing mygrep, ripgrep, and GNU grep.

Options:
    --warm          Run warm benchmarks (OS cache active, default)
    --cold          Run cold benchmarks (clear cache before each run)
    --corpus TYPE   Corpus type: all, code, log, binary (default: all)
    --pattern TYPE  Pattern type: common, rare, frequent, or custom string (default: common)
    --warmup N      Number of warmup runs (default: ${WARMUP_RUNS})
    --runs N        Number of benchmark runs (default: ${BENCH_RUNS})
    --dry-run       Show commands without executing
    --verbose       Enable verbose output
    --skip-binary   Skip binary file benchmark
    -h, --help      Show this help message

Examples:
    $(basename "$0")                        # Run all warm benchmarks
    $(basename "$0") --cold                 # Run all cold benchmarks
    $(basename "$0") --corpus code          # Benchmark only code tree
    $(basename "$0") --pattern "TODO"       # Search for custom pattern
    $(basename "$0") --corpus log --cold    # Cold benchmark on log file

Environment variables:
    MYGREP_BIN      Path to mygrep binary (default: ./bin/mygrep)
    RG_BIN          Path to ripgrep binary (default: rg)
    GREP_BIN        Path to GNU grep binary (default: ggrep on macOS, grep on Linux)

Results are saved to: ${RESULTS_DIR}/
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --warm)
                RUN_COLD=false
                ;;
            --cold)
                RUN_COLD=true
                ;;
            --corpus)
                shift
                CORPUS_TYPE="$1"
                ;;
            --pattern)
                shift
                PATTERN_TYPE="$1"
                ;;
            --warmup)
                shift
                WARMUP_RUNS="$1"
                ;;
            --runs)
                shift
                BENCH_RUNS="$1"
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --skip-binary)
                SKIP_BINARY_CHECK=true
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
        shift
    done

    # Change to repository root
    cd "${SCRIPT_DIR}/.."

    # Banner
    echo "============================================================"
    echo "  mygrep Benchmark Suite"
    echo "============================================================"
    echo ""

    # Show configuration
    local cache_mode
    if [[ "${RUN_COLD}" == true ]]; then cache_mode="cold"; else cache_mode="warm"; fi
    log_info "Configuration:"
    log_info "  Mode: ${cache_mode}"
    log_info "  Corpus: ${CORPUS_TYPE}"
    log_info "  Pattern: ${PATTERN_TYPE} ($(get_search_pattern "${PATTERN_TYPE}"))"
    log_info "  Warmup runs: ${WARMUP_RUNS}"
    log_info "  Benchmark runs: ${BENCH_RUNS}"
    echo ""

    # Prerequisites check
    check_prerequisites
    echo ""

    # Check corpus exists
    if ! check_corpus "${CORPUS_TYPE}"; then
        exit 1
    fi
    echo ""

    # Create results directory
    mkdir -p "${RESULTS_DIR}"

    # Run benchmarks based on corpus type
    local start_time
    start_time=$(date +%s)

    case "${CORPUS_TYPE}" in
        all)
            run_code_tree_benchmark
            echo ""
            run_log_file_benchmark
            echo ""
            run_binary_file_benchmark
            ;;
        code)
            run_code_tree_benchmark
            ;;
        log)
            run_log_file_benchmark
            ;;
        binary)
            run_binary_file_benchmark
            ;;
        *)
            log_error "Unknown corpus type: ${CORPUS_TYPE}"
            exit 1
            ;;
    esac

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ""
    echo "============================================================"
    log_info "Benchmark complete!"
    log_info "Duration: ${duration} seconds"
    log_info "Results saved to: ${RESULTS_DIR}/"
    echo ""
    log_info "To generate a report, run:"
    log_info "  python3 ./bench/report.py"
    echo "============================================================"
}

main "$@"
