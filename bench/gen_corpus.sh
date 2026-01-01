#!/usr/bin/env bash
# bench/gen_corpus.sh - Generate benchmark corpus data
# Usage: ./bench/gen_corpus.sh [--all|--code|--log|--binary]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

random_word() {
    local words=("func" "var" "const" "type" "struct" "interface" "import" "package"
                 "return" "if" "else" "for" "range" "switch" "case" "default"
                 "break" "continue" "go" "defer" "select" "chan" "map" "make"
                 "new" "append" "len" "cap" "copy" "delete" "panic" "recover"
                 "TODO" "FIXME" "NOTE" "HACK" "XXX" "BUG" "OPTIMIZE" "REVIEW"
                 "the" "and" "for" "not" "with" "this" "that" "from" "have" "been")
    echo "${words[$((RANDOM % ${#words[@]}))]}"
}

random_identifier() {
    local prefixes=("get" "set" "is" "has" "create" "delete" "update" "find" "process" "handle")
    local suffixes=("User" "Data" "Config" "Service" "Handler" "Manager" "Factory" "Builder" "Client" "Server")
    echo "${prefixes[$((RANDOM % ${#prefixes[@]}))]}_${suffixes[$((RANDOM % ${#suffixes[@]}))]}"
}

#------------------------------------------------------------------------------
# Corpus A: Code tree (many small-medium files)
#------------------------------------------------------------------------------

generate_code_tree() {
    local corpus_dir="${CORPUS_DIR}/code_tree"
    local num_files="${CODE_TREE_NUM_FILES}"
    local avg_lines="${CODE_TREE_AVG_LINES}"

    log_info "Generating code tree corpus: ${num_files} files, ~${avg_lines} lines each"

    rm -rf "${corpus_dir}"
    mkdir -p "${corpus_dir}"

    # Create subdirectory structure
    local subdirs=("src" "pkg" "internal" "cmd" "api" "util" "config" "test" "docs" "scripts")
    for subdir in "${subdirs[@]}"; do
        mkdir -p "${corpus_dir}/${subdir}"
    done

    for i in $(seq 1 "${num_files}"); do
        # Distribute files across subdirectories
        local subdir="${subdirs[$((i % ${#subdirs[@]}))]}"
        local filename="${corpus_dir}/${subdir}/file_$(printf '%04d' "$i").go"

        # Vary line count around average (50% to 150%)
        local line_count=$((avg_lines / 2 + RANDOM % avg_lines))

        {
            echo "package ${subdir}"
            echo ""
            echo "// File: file_$(printf '%04d' "$i").go"
            echo "// Auto-generated for benchmark corpus"
            echo ""

            # Generate imports
            echo "import ("
            echo '    "fmt"'
            echo '    "strings"'
            echo '    "os"'
            echo ")"
            echo ""

            # Generate structs and functions
            local struct_count=$((line_count / 30 + 1))
            for j in $(seq 1 "${struct_count}"); do
                local struct_name="$(random_identifier)_${j}"
                echo "// ${struct_name} handles $(random_word) operations"
                echo "// TODO: Add documentation for this struct"
                echo "type ${struct_name} struct {"
                echo "    ID       int"
                echo "    Name     string"
                echo "    Data     []byte"
                echo "    Config   map[string]interface{}"
                echo "}"
                echo ""
                echo "// New${struct_name} creates a new instance"
                echo "func New${struct_name}(name string) *${struct_name} {"
                echo "    // TODO: Implement proper initialization"
                echo "    return &${struct_name}{"
                echo "        Name: name,"
                echo "    }"
                echo "}"
                echo ""
                echo "// Process handles the main logic"
                echo "func (s *${struct_name}) Process() error {"
                echo "    // NOTE: This is a placeholder implementation"
                echo "    if s.Name == \"\" {"
                echo "        return fmt.Errorf(\"name is required\")"
                echo "    }"
                echo "    // FIXME: Add proper error handling"
                echo "    fmt.Println(\"Processing:\", s.Name)"
                echo "    return nil"
                echo "}"
                echo ""
            done

            # Fill remaining lines with comments and code
            local remaining=$((line_count - struct_count * 25))
            for _ in $(seq 1 "${remaining}"); do
                case $((RANDOM % 5)) in
                    0) echo "// $(random_word) $(random_word) $(random_word)" ;;
                    1) echo "var _ = strings.Contains(\"the quick brown fox\", \"$(random_word)\")" ;;
                    2) echo "// TODO: Refactor this section" ;;
                    3) echo "const $(random_identifier) = \"$(random_word)_value\"" ;;
                    4) echo "// NOTE: $(random_word) is deprecated, use $(random_word) instead" ;;
                esac
            done
        } > "${filename}"

        # Progress indicator
        if ((i % 100 == 0)); then
            log_info "  Generated ${i}/${num_files} files..."
        fi
    done

    # Calculate total size
    local total_size
    total_size=$(du -sh "${corpus_dir}" | cut -f1)
    local file_count
    file_count=$(find "${corpus_dir}" -type f | wc -l | tr -d ' ')

    log_info "Code tree corpus generated: ${file_count} files, ${total_size}"
}

#------------------------------------------------------------------------------
# Corpus B: Large single log file
#------------------------------------------------------------------------------

generate_log_file() {
    local corpus_dir="${CORPUS_DIR}/log"
    local num_lines="${LOG_FILE_NUM_LINES}"
    local line_length="${LOG_FILE_LINE_LENGTH}"
    local log_file="${corpus_dir}/access.log"

    log_info "Generating log file corpus: ${num_lines} lines, ~${line_length} chars each"

    rm -rf "${corpus_dir}"
    mkdir -p "${corpus_dir}"

    # Log levels and messages
    local levels=("DEBUG" "INFO" "WARN" "ERROR" "FATAL")
    local services=("api-gateway" "auth-service" "user-service" "data-processor" "cache-manager"
                   "queue-worker" "scheduler" "notifier" "logger" "monitor")
    local actions=("Request received" "Processing started" "Cache hit" "Cache miss" "Query executed"
                  "Connection established" "Connection closed" "Timeout occurred" "Retry attempt"
                  "Operation completed" "Validation failed" "Authentication successful" "TODO: investigate"
                  "Rate limit exceeded" "Circuit breaker triggered" "Fallback activated")
    local ips=("192.168.1" "10.0.0" "172.16.0" "192.168.100" "10.10.10")

    {
        for i in $(seq 1 "${num_lines}"); do
            local timestamp="2024-01-$((i % 28 + 1))T$((i % 24)):$((i % 60)):$((i % 60)).$(printf '%03d' $((i % 1000)))Z"
            local level="${levels[$((RANDOM % ${#levels[@]}))]}"
            local service="${services[$((RANDOM % ${#services[@]}))]}"
            local action="${actions[$((RANDOM % ${#actions[@]}))]}"
            local ip="${ips[$((RANDOM % ${#ips[@]}))]}.$(( RANDOM % 255 ))"
            local request_id="req-$(printf '%08x' $((RANDOM * RANDOM)))"
            local user_id="user-$(printf '%04d' $((RANDOM % 10000)))"
            local duration="$((RANDOM % 5000))ms"

            # JSON-like log format (common in production)
            echo "{\"timestamp\":\"${timestamp}\",\"level\":\"${level}\",\"service\":\"${service}\",\"message\":\"${action}\",\"ip\":\"${ip}\",\"request_id\":\"${request_id}\",\"user_id\":\"${user_id}\",\"duration\":\"${duration}\",\"extra\":\"the quick brown fox jumps over the lazy dog\"}"

            # Progress indicator
            if ((i % 100000 == 0)); then
                log_info "  Generated ${i}/${num_lines} lines..." >&2
            fi
        done
    } > "${log_file}"

    local file_size
    file_size=$(du -sh "${log_file}" | cut -f1)
    log_info "Log file corpus generated: ${log_file} (${file_size})"
}

#------------------------------------------------------------------------------
# Corpus C: Binary file (to test binary detection/handling)
#------------------------------------------------------------------------------

generate_binary_file() {
    local corpus_dir="${CORPUS_DIR}/binary"
    local size_mb="${BINARY_FILE_SIZE_MB}"
    local binary_file="${corpus_dir}/random.bin"

    log_info "Generating binary corpus: ${size_mb} MB"

    rm -rf "${corpus_dir}"
    mkdir -p "${corpus_dir}"

    # Generate random binary data with some embedded text patterns
    # This tests how tools handle binary files (should skip or warn)
    dd if=/dev/urandom of="${binary_file}" bs=1M count="${size_mb}" 2>/dev/null

    # Embed some text patterns in the binary file for testing
    # This simulates binary files that might have embedded strings
    local text_file="${corpus_dir}/embedded_text.txt"
    {
        echo "EMBEDDED_STRING_START"
        for i in $(seq 1 100); do
            echo "This is embedded text line ${i} with TODO and the word 'the' appearing multiple times"
        done
        echo "EMBEDDED_STRING_END"
    } > "${text_file}"

    # Append text to binary file
    cat "${text_file}" >> "${binary_file}"
    rm "${text_file}"

    local file_size
    file_size=$(du -sh "${binary_file}" | cut -f1)
    log_info "Binary corpus generated: ${binary_file} (${file_size})"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate benchmark corpus data.

Options:
    --all       Generate all corpus types (default)
    --code      Generate code tree corpus only (type A)
    --log       Generate log file corpus only (type B)
    --binary    Generate binary corpus only (type C)
    --clean     Remove all generated corpus data
    -h, --help  Show this help message

Corpus types:
    A (code):   Many small-medium source code files (~${CODE_TREE_NUM_FILES} files)
    B (log):    Single large log file (~${LOG_FILE_NUM_LINES} lines)
    C (binary): Binary file with embedded text (~${BINARY_FILE_SIZE_MB} MB)

Examples:
    $(basename "$0") --all     # Generate all corpus types
    $(basename "$0") --code    # Generate only code tree
    $(basename "$0") --clean   # Remove all corpus data
EOF
}

main() {
    local gen_code=false
    local gen_log=false
    local gen_binary=false
    local clean=false

    # Parse arguments
    if [[ $# -eq 0 ]]; then
        gen_code=true
        gen_log=true
        gen_binary=true
    else
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --all)
                    gen_code=true
                    gen_log=true
                    gen_binary=true
                    ;;
                --code)
                    gen_code=true
                    ;;
                --log)
                    gen_log=true
                    ;;
                --binary)
                    gen_binary=true
                    ;;
                --clean)
                    clean=true
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
    fi

    # Change to repository root
    cd "${SCRIPT_DIR}/.."

    if [[ "${clean}" == true ]]; then
        log_info "Cleaning corpus directory..."
        rm -rf "${CORPUS_DIR:?}/code_tree" "${CORPUS_DIR:?}/log" "${CORPUS_DIR:?}/binary"
        log_info "Corpus data cleaned"
        exit 0
    fi

    log_info "Starting corpus generation..."
    log_info "Corpus directory: ${CORPUS_DIR}"
    echo ""

    if [[ "${gen_code}" == true ]]; then
        generate_code_tree
        echo ""
    fi

    if [[ "${gen_log}" == true ]]; then
        generate_log_file
        echo ""
    fi

    if [[ "${gen_binary}" == true ]]; then
        generate_binary_file
        echo ""
    fi

    log_info "Corpus generation complete!"

    # Show summary
    echo ""
    log_info "Corpus summary:"
    if [[ -d "${CORPUS_DIR}/code_tree" ]]; then
        echo "  - Code tree: $(find "${CORPUS_DIR}/code_tree" -type f | wc -l | tr -d ' ') files, $(du -sh "${CORPUS_DIR}/code_tree" | cut -f1)"
    fi
    if [[ -f "${CORPUS_DIR}/log/access.log" ]]; then
        echo "  - Log file: $(wc -l < "${CORPUS_DIR}/log/access.log" | tr -d ' ') lines, $(du -sh "${CORPUS_DIR}/log/access.log" | cut -f1)"
    fi
    if [[ -f "${CORPUS_DIR}/binary/random.bin" ]]; then
        echo "  - Binary file: $(du -sh "${CORPUS_DIR}/binary/random.bin" | cut -f1)"
    fi
}

main "$@"
