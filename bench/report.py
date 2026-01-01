#!/usr/bin/env python3
"""
bench/report.py - Aggregate and report benchmark results

This script reads hyperfine JSON output files and generates a comparison report
showing performance metrics for mygrep, ripgrep, and GNU grep.

Usage:
    python3 bench/report.py [OPTIONS]

Options:
    --results-dir PATH    Directory containing JSON results (default: ./bench/results)
    --latest              Only process the most recent result for each benchmark type
    --compare FILE1 FILE2 Compare two specific result files
    --json                Output report in JSON format
    --csv                 Output report in CSV format
    -h, --help            Show this help message
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from statistics import mean, median, stdev
from typing import Optional


@dataclass
class BenchmarkResult:
    """Represents a single tool's benchmark result."""
    command: str
    mean: float
    stddev: float
    median: float
    min: float
    max: float
    times: list[float]

    @classmethod
    def from_hyperfine(cls, data: dict) -> "BenchmarkResult":
        """Create from hyperfine JSON result."""
        return cls(
            command=data.get("command", "unknown"),
            mean=data.get("mean", 0),
            stddev=data.get("stddev", 0),
            median=data.get("median", 0),
            min=data.get("min", 0),
            max=data.get("max", 0),
            times=data.get("times", []),
        )


@dataclass
class BenchmarkRun:
    """Represents a complete benchmark run with multiple tools."""
    name: str
    timestamp: str
    pattern: str
    target_path: str
    size_mb: float
    file_count: int
    cold_run: bool
    results: list[BenchmarkResult]

    @classmethod
    def from_json_file(cls, filepath: Path) -> Optional["BenchmarkRun"]:
        """Load benchmark run from JSON file."""
        try:
            with open(filepath, "r") as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Failed to load {filepath}: {e}", file=sys.stderr)
            return None

        metadata = data.get("metadata", {})
        results = [
            BenchmarkResult.from_hyperfine(r)
            for r in data.get("results", [])
        ]

        return cls(
            name=metadata.get("benchmark_name", filepath.stem),
            timestamp=metadata.get("timestamp", "unknown"),
            pattern=metadata.get("pattern", "unknown"),
            target_path=metadata.get("target_path", "unknown"),
            size_mb=metadata.get("size_mb", 0),
            file_count=metadata.get("file_count", 1),
            cold_run=metadata.get("cold_run", False),
            results=results,
        )


def format_time(seconds: float) -> str:
    """Format time in human-readable format."""
    if seconds < 0.001:
        return f"{seconds * 1_000_000:.1f} µs"
    elif seconds < 1:
        return f"{seconds * 1000:.1f} ms"
    else:
        return f"{seconds:.3f} s"


def format_throughput(size_mb: float, time_seconds: float) -> str:
    """Format throughput in MB/s."""
    if time_seconds <= 0:
        return "N/A"
    throughput = size_mb / time_seconds
    return f"{throughput:.1f} MB/s"


def calculate_speedup(base_time: float, compare_time: float) -> str:
    """Calculate speedup ratio."""
    if compare_time <= 0:
        return "N/A"
    ratio = base_time / compare_time
    if ratio >= 1:
        return f"{ratio:.2f}x faster"
    else:
        return f"{1/ratio:.2f}x slower"


def get_tool_name(command: str) -> str:
    """Extract tool name from command."""
    cmd_lower = command.lower()
    if "mygrep" in cmd_lower:
        return "mygrep"
    elif "ripgrep" in cmd_lower or "rg " in command or "rg'" in command:
        return "ripgrep"
    elif "ggrep" in cmd_lower or "gnu-grep" in cmd_lower or "/grep" in command:
        return "gnu-grep"
    return command.split()[0]


def print_separator(char: str = "-", width: int = 80):
    """Print a separator line."""
    print(char * width)


def print_benchmark_report(run: BenchmarkRun, verbose: bool = False):
    """Print a detailed report for a single benchmark run."""
    cache_mode = "cold" if run.cold_run else "warm"

    print()
    print_separator("=")
    print(f"Benchmark: {run.name}")
    print_separator("=")
    print(f"  Timestamp:   {run.timestamp}")
    print(f"  Pattern:     '{run.pattern}'")
    print(f"  Target:      {run.target_path}")
    print(f"  Size:        {run.size_mb:.1f} MB ({run.file_count} files)")
    print(f"  Cache mode:  {cache_mode}")
    print()

    if not run.results:
        print("  No results available")
        return

    # Sort results by mean time (fastest first)
    sorted_results = sorted(run.results, key=lambda r: r.mean)
    fastest = sorted_results[0]

    # Header
    print(f"  {'Tool':<15} {'Mean':<12} {'Median':<12} {'Stddev':<12} {'Min':<12} {'Max':<12} {'Throughput':<12} {'vs Fastest':<15}")
    print_separator("-")

    for result in sorted_results:
        tool_name = get_tool_name(result.command)
        throughput = format_throughput(run.size_mb, result.mean)

        if result == fastest:
            comparison = "baseline"
        else:
            comparison = calculate_speedup(result.mean, fastest.mean)

        print(f"  {tool_name:<15} "
              f"{format_time(result.mean):<12} "
              f"{format_time(result.median):<12} "
              f"{format_time(result.stddev):<12} "
              f"{format_time(result.min):<12} "
              f"{format_time(result.max):<12} "
              f"{throughput:<12} "
              f"{comparison:<15}")

    print()

    # Summary
    mygrep_result = next((r for r in run.results if "mygrep" in get_tool_name(r.command)), None)
    if mygrep_result:
        print("  Summary:")
        for result in sorted_results:
            tool_name = get_tool_name(result.command)
            if tool_name != "mygrep":
                speedup = calculate_speedup(mygrep_result.mean, result.mean)
                print(f"    mygrep vs {tool_name}: {speedup}")


def print_summary_table(runs: list[BenchmarkRun]):
    """Print a summary table comparing all benchmark runs."""
    print()
    print_separator("=")
    print("OVERALL SUMMARY")
    print_separator("=")
    print()

    # Collect all unique tools
    all_tools = set()
    for run in runs:
        for result in run.results:
            all_tools.add(get_tool_name(result.command))

    tool_list = sorted(all_tools)

    # Header
    header = f"  {'Benchmark':<30}"
    for tool in tool_list:
        header += f" {tool:<15}"
    header += " Winner"
    print(header)
    print_separator("-")

    # Data rows
    for run in runs:
        cache_mode = "cold" if run.cold_run else "warm"
        row_name = f"{run.name} ({cache_mode})"
        row = f"  {row_name:<30}"

        result_map = {get_tool_name(r.command): r for r in run.results}
        sorted_results = sorted(run.results, key=lambda r: r.mean)
        winner = get_tool_name(sorted_results[0].command) if sorted_results else "N/A"

        for tool in tool_list:
            if tool in result_map:
                row += f" {format_time(result_map[tool].mean):<15}"
            else:
                row += f" {'N/A':<15}"

        row += f" {winner}"
        print(row)

    print()


def print_csv_report(runs: list[BenchmarkRun]):
    """Print report in CSV format."""
    # Header
    print("benchmark,cache_mode,pattern,size_mb,file_count,tool,mean_s,median_s,stddev_s,min_s,max_s,throughput_mbs")

    for run in runs:
        cache_mode = "cold" if run.cold_run else "warm"
        for result in run.results:
            tool_name = get_tool_name(result.command)
            throughput = run.size_mb / result.mean if result.mean > 0 else 0
            print(f"{run.name},{cache_mode},{run.pattern},{run.size_mb},{run.file_count},"
                  f"{tool_name},{result.mean:.6f},{result.median:.6f},{result.stddev:.6f},"
                  f"{result.min:.6f},{result.max:.6f},{throughput:.2f}")


def print_json_report(runs: list[BenchmarkRun]):
    """Print report in JSON format."""
    output = []
    for run in runs:
        run_data = {
            "benchmark": run.name,
            "timestamp": run.timestamp,
            "pattern": run.pattern,
            "target_path": run.target_path,
            "size_mb": run.size_mb,
            "file_count": run.file_count,
            "cold_run": run.cold_run,
            "results": []
        }
        for result in run.results:
            result_data = {
                "tool": get_tool_name(result.command),
                "mean_s": result.mean,
                "median_s": result.median,
                "stddev_s": result.stddev,
                "min_s": result.min,
                "max_s": result.max,
                "throughput_mbs": run.size_mb / result.mean if result.mean > 0 else 0,
            }
            run_data["results"].append(result_data)
        output.append(run_data)

    print(json.dumps(output, indent=2))


def find_result_files(results_dir: Path, latest_only: bool = False) -> list[Path]:
    """Find all JSON result files in the results directory."""
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}", file=sys.stderr)
        return []

    json_files = sorted(results_dir.glob("*.json"))

    if not json_files:
        print(f"No result files found in {results_dir}", file=sys.stderr)
        return []

    if latest_only:
        # Group by benchmark type (everything before the timestamp)
        groups: dict[str, list[Path]] = {}
        for f in json_files:
            # Extract benchmark type from filename (remove timestamp suffix)
            parts = f.stem.rsplit("_", 2)
            if len(parts) >= 3:
                bench_type = "_".join(parts[:-2])
            else:
                bench_type = f.stem

            if bench_type not in groups:
                groups[bench_type] = []
            groups[bench_type].append(f)

        # Get the latest file from each group
        latest_files = []
        for bench_type, files in groups.items():
            latest_files.append(sorted(files)[-1])

        return sorted(latest_files)

    return json_files


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate and report benchmark results",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=Path("./bench/results"),
        help="Directory containing JSON results"
    )
    parser.add_argument(
        "--latest",
        action="store_true",
        help="Only process the most recent result for each benchmark type"
    )
    parser.add_argument(
        "--compare",
        nargs=2,
        metavar=("FILE1", "FILE2"),
        help="Compare two specific result files"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output report in JSON format"
    )
    parser.add_argument(
        "--csv",
        action="store_true",
        help="Output report in CSV format"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show verbose output"
    )

    args = parser.parse_args()

    # Find result files
    if args.compare:
        result_files = [Path(f) for f in args.compare]
    else:
        result_files = find_result_files(args.results_dir, args.latest)

    if not result_files:
        print("No benchmark results to process.", file=sys.stderr)
        sys.exit(1)

    # Load results
    runs = []
    for filepath in result_files:
        run = BenchmarkRun.from_json_file(filepath)
        if run:
            runs.append(run)

    if not runs:
        print("Failed to load any benchmark results.", file=sys.stderr)
        sys.exit(1)

    # Output report
    if args.json:
        print_json_report(runs)
    elif args.csv:
        print_csv_report(runs)
    else:
        print()
        print("=" * 80)
        print("                      MYGREP BENCHMARK REPORT")
        print("=" * 80)
        print(f"  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"  Results:   {len(runs)} benchmark run(s) from {args.results_dir}")

        for run in runs:
            print_benchmark_report(run, args.verbose)

        if len(runs) > 1:
            print_summary_table(runs)

        print()
        print("Notes:")
        print("  - Times are wall-clock time (lower is better)")
        print("  - Throughput is calculated as size_mb / mean_time")
        print("  - 'warm' means OS page cache is active")
        print("  - 'cold' means page cache was cleared before each run")
        print()


if __name__ == "__main__":
    main()
