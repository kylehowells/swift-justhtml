#!/usr/bin/env python3
"""
Cross-implementation benchmark comparison.
Runs Swift, Python, and JavaScript parsers and compares results.
Generates a markdown report with git commit info.
"""

import subprocess
import sys
import os
import json
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
SAMPLES_DIR = SCRIPT_DIR / "samples"
SWIFT_PROJECT_ROOT = SCRIPT_DIR.parent
JUSTHTML_ROOT = SWIFT_PROJECT_ROOT.parent

def get_git_info(repo_path):
    """Get git commit hash and date for a repository."""
    try:
        # Get commit hash
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_path,
            capture_output=True,
            text=True
        )
        commit_hash = result.stdout.strip()[:12] if result.returncode == 0 else "unknown"

        # Get commit date
        result = subprocess.run(
            ["git", "log", "-1", "--format=%ci"],
            cwd=repo_path,
            capture_output=True,
            text=True
        )
        commit_date = result.stdout.strip()[:10] if result.returncode == 0 else "unknown"

        # Get branch name
        result = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=repo_path,
            capture_output=True,
            text=True
        )
        branch = result.stdout.strip() if result.returncode == 0 else "unknown"

        return {
            'commit': commit_hash,
            'date': commit_date,
            'branch': branch
        }
    except Exception as e:
        return {'commit': 'unknown', 'date': 'unknown', 'branch': 'unknown'}

def download_samples():
    """Download sample HTML files if not present."""
    SAMPLES_DIR.mkdir(exist_ok=True)

    samples = [
        ("https://en.wikipedia.org/wiki/HTML", "wikipedia_html.html"),
        ("https://en.wikipedia.org/wiki/Swift_(programming_language)", "wikipedia_swift.html"),
        ("https://en.wikipedia.org/wiki/World_War_II", "wikipedia_ww2.html"),
        ("https://en.wikipedia.org/wiki/List_of_countries_by_population_(United_Nations)", "wikipedia_countries.html"),
        ("https://news.ycombinator.com/", "hackernews.html"),
    ]

    for url, filename in samples:
        filepath = SAMPLES_DIR / filename
        if not filepath.exists():
            print(f"Downloading {filename}...", file=sys.stderr)
            subprocess.run(["curl", "-sL", url, "-o", str(filepath)], check=True)
        else:
            print(f"Using cached {filename}", file=sys.stderr)

def run_swift_benchmark():
    """Build and run the Swift benchmark."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Building and running Swift benchmark...", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    # Build release version
    result = subprocess.run(
        ["swift", "build", "-c", "release", "--product", "Benchmark"],
        cwd=SWIFT_PROJECT_ROOT,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Swift build failed:\n{result.stderr}", file=sys.stderr)
        return None

    # Run benchmark
    result = subprocess.run(
        ["swift", "run", "-c", "release", "Benchmark"],
        cwd=SWIFT_PROJECT_ROOT,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Swift benchmark failed:\n{result.stderr}", file=sys.stderr)
        return None

    print(result.stderr, file=sys.stderr)
    return json.loads(result.stdout)

def run_python_benchmark():
    """Run the Python benchmark."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Running Python benchmark...", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "benchmark_python.py")],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Python benchmark failed:\n{result.stderr}", file=sys.stderr)
        return None

    print(result.stderr, file=sys.stderr)
    return json.loads(result.stdout)

def run_js_benchmark():
    """Run the JavaScript benchmark."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Running JavaScript benchmark...", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    result = subprocess.run(
        ["node", str(SCRIPT_DIR / "benchmark_js.mjs")],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"JavaScript benchmark failed:\n{result.stderr}", file=sys.stderr)
        return None

    print(result.stderr, file=sys.stderr)
    return json.loads(result.stdout)

def compare_outputs(swift_results, python_results, js_results):
    """Compare outputs from all three implementations."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Output Comparison", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    # Build lookup by filename
    swift_by_file = {r['file']: r for r in swift_results} if swift_results else {}
    python_by_file = {r['file']: r for r in python_results} if python_results else {}
    js_by_file = {r['file']: r for r in js_results} if js_results else {}

    all_files = set(swift_by_file.keys()) | set(python_by_file.keys()) | set(js_by_file.keys())

    all_match = True
    file_results = {}
    for filename in sorted(all_files):
        swift_out = swift_by_file.get(filename, {}).get('output', '')
        python_out = python_by_file.get(filename, {}).get('output', '')
        js_out = js_by_file.get(filename, {}).get('output', '')

        swift_python_match = swift_out == python_out if swift_out and python_out else None
        swift_js_match = swift_out == js_out if swift_out and js_out else None
        python_js_match = python_out == js_out if python_out and js_out else None

        status = "OK" if (swift_python_match and swift_js_match and python_js_match) else "MISMATCH"
        if status == "MISMATCH":
            all_match = False

        file_results[filename] = status
        print(f"  {filename}: {status}", file=sys.stderr)
        if status == "MISMATCH":
            print(f"    Swift==Python: {swift_python_match}", file=sys.stderr)
            print(f"    Swift==JS: {swift_js_match}", file=sys.stderr)
            print(f"    Python==JS: {python_js_match}", file=sys.stderr)

    return all_match, file_results

def generate_markdown_report(swift_results, python_results, js_results, all_match, file_results, git_info):
    """Generate a markdown report with benchmark results."""
    lines = []

    # Header
    lines.append("# Cross-Implementation Benchmark Results")
    lines.append("")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    # Git info
    lines.append("## Repository Versions")
    lines.append("")
    lines.append("| Project | Branch | Commit | Date |")
    lines.append("|---------|--------|--------|------|")
    for name, info in git_info.items():
        lines.append(f"| {name} | {info['branch']} | `{info['commit']}` | {info['date']} |")
    lines.append("")

    # Output comparison
    lines.append("## Output Consistency")
    lines.append("")
    if all_match:
        lines.append("All implementations produce **identical output** for all test files.")
    else:
        lines.append("**WARNING:** Output mismatch detected!")
    lines.append("")
    lines.append("| File | Status |")
    lines.append("|------|--------|")
    for filename, status in sorted(file_results.items()):
        emoji = "✅" if status == "OK" else "❌"
        lines.append(f"| {filename} | {emoji} {status} |")
    lines.append("")

    # Performance comparison
    lines.append("## Performance Comparison")
    lines.append("")

    swift_by_file = {r['file']: r for r in swift_results} if swift_results else {}
    python_by_file = {r['file']: r for r in python_results} if python_results else {}
    js_by_file = {r['file']: r for r in js_results} if js_results else {}

    all_files = set(swift_by_file.keys()) | set(python_by_file.keys()) | set(js_by_file.keys())

    lines.append("| File | Size | Swift | Python | JavaScript | Swift vs Python | Swift vs JS |")
    lines.append("|------|------|-------|--------|------------|-----------------|-------------|")

    total_swift = 0
    total_python = 0
    total_js = 0

    for filename in sorted(all_files):
        swift_r = swift_by_file.get(filename, {})
        python_r = python_by_file.get(filename, {})
        js_r = js_by_file.get(filename, {})

        size = swift_r.get('size_bytes') or python_r.get('size_bytes') or js_r.get('size_bytes', 0)
        size_str = f"{size/1024:.0f} KB"

        swift_ms = swift_r.get('avg_ms', 0)
        python_ms = python_r.get('avg_ms', 0)
        js_ms = js_r.get('avg_ms', 0)

        total_swift += swift_ms
        total_python += python_ms
        total_js += js_ms

        swift_str = f"{swift_ms:.2f} ms" if swift_ms else "N/A"
        python_str = f"{python_ms:.2f} ms" if python_ms else "N/A"
        js_str = f"{js_ms:.2f} ms" if js_ms else "N/A"

        # Speed ratios
        swift_py_ratio = python_ms / swift_ms if swift_ms and python_ms else 0
        swift_js_ratio = js_ms / swift_ms if swift_ms and js_ms else 0

        ratio_py_str = f"{swift_py_ratio:.2f}x faster" if swift_py_ratio > 1 else f"{1/swift_py_ratio:.2f}x slower" if swift_py_ratio else "N/A"
        ratio_js_str = f"{swift_js_ratio:.2f}x faster" if swift_js_ratio > 1 else f"{1/swift_js_ratio:.2f}x slower" if swift_js_ratio else "N/A"

        lines.append(f"| {filename} | {size_str} | {swift_str} | {python_str} | {js_str} | {ratio_py_str} | {ratio_js_str} |")

    # Totals
    swift_py_total = total_python / total_swift if total_swift else 0
    swift_js_total = total_js / total_swift if total_swift else 0

    ratio_py_total = f"{swift_py_total:.2f}x faster" if swift_py_total > 1 else f"{1/swift_py_total:.2f}x slower" if swift_py_total else "N/A"
    ratio_js_total = f"{swift_js_total:.2f}x faster" if swift_js_total > 1 else f"{1/swift_js_total:.2f}x slower" if swift_js_total else "N/A"

    lines.append(f"| **TOTAL** | | **{total_swift:.0f} ms** | **{total_python:.0f} ms** | **{total_js:.0f} ms** | **{ratio_py_total}** | **{ratio_js_total}** |")
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- **Swift** total parse time: {total_swift:.0f} ms")
    lines.append(f"- **Python** total parse time: {total_python:.0f} ms")
    lines.append(f"- **JavaScript** total parse time: {total_js:.0f} ms")
    lines.append("")

    if total_swift and total_python and total_js:
        fastest = min(total_swift, total_python, total_js)
        if fastest == total_js:
            lines.append("**JavaScript** is the fastest implementation (V8 JIT optimization).")
        elif fastest == total_swift:
            lines.append("**Swift** is the fastest implementation.")
        else:
            lines.append("**Python** is the fastest implementation.")
        lines.append("")
        lines.append(f"Swift is **{total_python/total_swift:.1f}x faster** than Python.")
        lines.append(f"JavaScript is **{total_swift/total_js:.1f}x faster** than Swift.")
    lines.append("")

    # Test files info
    lines.append("## Test Files")
    lines.append("")
    lines.append("| File | Source | Size |")
    lines.append("|------|--------|------|")
    for filename in sorted(all_files):
        size = swift_by_file.get(filename, {}).get('size_bytes', 0) or \
               python_by_file.get(filename, {}).get('size_bytes', 0) or \
               js_by_file.get(filename, {}).get('size_bytes', 0)
        if 'wikipedia' in filename:
            source = "Wikipedia"
        elif 'hackernews' in filename:
            source = "Hacker News"
        elif 'synthetic' in filename:
            source = "Generated (stress test)"
        else:
            source = "Unknown"
        lines.append(f"| {filename} | {source} | {size:,} bytes |")
    lines.append("")

    return "\n".join(lines)

def print_summary(swift_results, python_results, js_results):
    """Print performance summary table."""
    print("\n" + "=" * 60)
    print("PERFORMANCE COMPARISON")
    print("=" * 60)

    # Header
    print(f"\n{'File':<25} {'Size':>10} | {'Swift':>10} {'Python':>10} {'JS':>10} | {'Swift/Py':>8} {'Swift/JS':>8}")
    print("-" * 100)

    swift_by_file = {r['file']: r for r in swift_results} if swift_results else {}
    python_by_file = {r['file']: r for r in python_results} if python_results else {}
    js_by_file = {r['file']: r for r in js_results} if js_results else {}

    all_files = set(swift_by_file.keys()) | set(python_by_file.keys()) | set(js_by_file.keys())

    total_swift = 0
    total_python = 0
    total_js = 0

    for filename in sorted(all_files):
        swift_r = swift_by_file.get(filename, {})
        python_r = python_by_file.get(filename, {})
        js_r = js_by_file.get(filename, {})

        size = swift_r.get('size_bytes') or python_r.get('size_bytes') or js_r.get('size_bytes', 0)
        size_kb = f"{size/1024:.0f}KB"

        swift_ms = swift_r.get('avg_ms', 0)
        python_ms = python_r.get('avg_ms', 0)
        js_ms = js_r.get('avg_ms', 0)

        total_swift += swift_ms
        total_python += python_ms
        total_js += js_ms

        swift_str = f"{swift_ms:.2f}ms" if swift_ms else "N/A"
        python_str = f"{python_ms:.2f}ms" if python_ms else "N/A"
        js_str = f"{js_ms:.2f}ms" if js_ms else "N/A"

        # Speed ratios (how many times faster Swift is)
        swift_py_ratio = python_ms / swift_ms if swift_ms and python_ms else 0
        swift_js_ratio = js_ms / swift_ms if swift_ms and js_ms else 0

        ratio_py_str = f"{swift_py_ratio:.1f}x" if swift_py_ratio else "N/A"
        ratio_js_str = f"{swift_js_ratio:.1f}x" if swift_js_ratio else "N/A"

        print(f"{filename:<25} {size_kb:>10} | {swift_str:>10} {python_str:>10} {js_str:>10} | {ratio_py_str:>8} {ratio_js_str:>8}")

    print("-" * 100)

    # Totals
    swift_py_total = total_python / total_swift if total_swift else 0
    swift_js_total = total_js / total_swift if total_swift else 0

    print(f"{'TOTAL':<25} {'':<10} | {total_swift:>9.0f}ms {total_python:>9.0f}ms {total_js:>9.0f}ms | {swift_py_total:>7.1f}x {swift_js_total:>7.1f}x")

    print("\n(Higher ratio = Swift is faster by that factor)")

def main():
    # Get git info for all three projects
    print("Gathering git information...", file=sys.stderr)
    git_info = {
        'swift-justhtml': get_git_info(SWIFT_PROJECT_ROOT),
        'justhtml (Python)': get_git_info(JUSTHTML_ROOT / 'justhtml'),
        'justjshtml (JavaScript)': get_git_info(JUSTHTML_ROOT / 'justjshtml'),
    }

    # Download samples if needed
    download_samples()

    # Run all benchmarks
    swift_results = run_swift_benchmark()
    python_results = run_python_benchmark()
    js_results = run_js_benchmark()

    # Compare outputs
    all_match, file_results = compare_outputs(swift_results, python_results, js_results)

    # Print performance summary
    print_summary(swift_results, python_results, js_results)

    # Generate markdown report
    markdown_report = generate_markdown_report(
        swift_results, python_results, js_results,
        all_match, file_results, git_info
    )

    # Save markdown report
    report_path = SCRIPT_DIR / "BENCHMARK_RESULTS.md"
    with open(report_path, 'w') as f:
        f.write(markdown_report)
    print(f"\nMarkdown report saved to: {report_path}")

    # Save raw results as JSON
    results = {
        'generated': datetime.now().isoformat(),
        'git_info': git_info,
        'swift': swift_results,
        'python': python_results,
        'javascript': js_results,
        'outputs_match': all_match
    }

    json_path = SCRIPT_DIR / "results.json"
    with open(json_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"JSON results saved to: {json_path}")

    if not all_match:
        print("\nWARNING: Output mismatch detected between implementations!")
        return 1

    return 0

if __name__ == '__main__':
    sys.exit(main())
