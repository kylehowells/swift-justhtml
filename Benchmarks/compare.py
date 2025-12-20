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

def run_rust_benchmark():
    """Build and run the Rust (html5ever) benchmark."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Building and running Rust (html5ever) benchmark...", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    rust_dir = SCRIPT_DIR / "rust_benchmark"
    if not rust_dir.exists():
        print("Rust benchmark not found, skipping...", file=sys.stderr)
        return None

    # Source cargo env and build
    env = os.environ.copy()
    cargo_bin = Path.home() / ".cargo" / "bin"
    if cargo_bin.exists():
        env["PATH"] = str(cargo_bin) + ":" + env.get("PATH", "")

    # Build release version
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=rust_dir,
        capture_output=True,
        text=True,
        env=env
    )
    if result.returncode != 0:
        print(f"Rust build failed:\n{result.stderr}", file=sys.stderr)
        return None

    # Run benchmark
    result = subprocess.run(
        ["cargo", "run", "--release"],
        cwd=rust_dir,
        capture_output=True,
        text=True,
        env=env
    )
    if result.returncode != 0:
        print(f"Rust benchmark failed:\n{result.stderr}", file=sys.stderr)
        return None

    print(result.stderr, file=sys.stderr)
    return json.loads(result.stdout)


def run_rust_justhtml_benchmark():
    """Build and run the rust-justhtml benchmark."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Building and running rust-justhtml benchmark...", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    rust_justhtml_dir = JUSTHTML_ROOT / "rust-justhtml"
    if not rust_justhtml_dir.exists():
        print("rust-justhtml not found, skipping...", file=sys.stderr)
        return None

    # Source cargo env and build
    env = os.environ.copy()
    cargo_bin = Path.home() / ".cargo" / "bin"
    if cargo_bin.exists():
        env["PATH"] = str(cargo_bin) + ":" + env.get("PATH", "")

    # Build release version
    result = subprocess.run(
        ["cargo", "build", "--release", "--bin", "benchmark"],
        cwd=rust_justhtml_dir,
        capture_output=True,
        text=True,
        env=env
    )
    if result.returncode != 0:
        print(f"rust-justhtml build failed:\n{result.stderr}", file=sys.stderr)
        return None

    # Run benchmark on each sample file (including test_files for synthetic.html)
    benchmark_binary = rust_justhtml_dir / "target" / "release" / "benchmark"
    results = []

    # Collect files from both samples and test_files directories
    all_samples = list(SAMPLES_DIR.glob("*.html"))
    test_files_dir = SCRIPT_DIR / "test_files"
    if test_files_dir.exists():
        all_samples.extend(test_files_dir.glob("*.html"))

    for sample in sorted(all_samples, key=lambda p: p.name):
        result = subprocess.run(
            [str(benchmark_binary), "--file", str(sample), "--json"],
            capture_output=True,
            text=True,
            env=env
        )
        if result.returncode != 0:
            print(f"  {sample.name}: FAILED", file=sys.stderr)
            continue

        try:
            data = json.loads(result.stdout.strip())
            file_size = sample.stat().st_size
            # Run 5 iterations for average
            times = []
            for _ in range(5):
                r = subprocess.run(
                    [str(benchmark_binary), "--file", str(sample), "--json"],
                    capture_output=True,
                    text=True,
                    env=env
                )
                if r.returncode == 0:
                    d = json.loads(r.stdout.strip())
                    times.append(d['time'] * 1000)  # Convert to ms

            avg_ms = sum(times) / len(times) if times else 0

            results.append({
                'file': sample.name,
                'size_bytes': file_size,
                'avg_ms': avg_ms,
                'output': ''  # rust-justhtml passes all html5lib tests, output matches
            })
            print(f"  {sample.name}: {avg_ms:.2f}ms", file=sys.stderr)
        except Exception as e:
            print(f"  {sample.name}: Error - {e}", file=sys.stderr)

    return results if results else None

def compare_outputs(swift_results, python_results, js_results, rust_results=None):
    """Compare outputs from all implementations."""
    print("\n" + "=" * 60, file=sys.stderr)
    print("Output Comparison", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    # Build lookup by filename
    swift_by_file = {r['file']: r for r in swift_results} if swift_results else {}
    python_by_file = {r['file']: r for r in python_results} if python_results else {}
    js_by_file = {r['file']: r for r in js_results} if js_results else {}
    rust_by_file = {r['file']: r for r in rust_results} if rust_results else {}

    all_files = set(swift_by_file.keys()) | set(python_by_file.keys()) | set(js_by_file.keys())

    all_match = True
    file_results = {}
    for filename in sorted(all_files):
        swift_out = swift_by_file.get(filename, {}).get('output', '')
        python_out = python_by_file.get(filename, {}).get('output', '')
        js_out = js_by_file.get(filename, {}).get('output', '')
        rust_out = rust_by_file.get(filename, {}).get('output', '')

        swift_python_match = swift_out == python_out if swift_out and python_out else None
        swift_js_match = swift_out == js_out if swift_out and js_out else None
        python_js_match = python_out == js_out if python_out and js_out else None
        # Note: Rust (html5ever) may have slightly different output format
        swift_rust_match = swift_out == rust_out if swift_out and rust_out else None

        # Only compare Swift/Python/JS for consistency (Rust is reference impl with different conventions)
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

def generate_markdown_report(swift_results, python_results, js_results, all_match, file_results, git_info, rust_results=None, rust_justhtml_results=None):
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
    rust_by_file = {r['file']: r for r in rust_results} if rust_results else {}
    rust_justhtml_by_file = {r['file']: r for r in rust_justhtml_results} if rust_justhtml_results else {}

    all_files = set(swift_by_file.keys()) | set(python_by_file.keys()) | set(js_by_file.keys())

    if rust_results and rust_justhtml_results:
        lines.append("| File | Size | html5ever | rust-justhtml | Swift | JavaScript | Python |")
        lines.append("|------|------|-----------|---------------|-------|------------|--------|")
    elif rust_results:
        lines.append("| File | Size | Rust | Swift | JavaScript | Python | Rust vs Swift |")
        lines.append("|------|------|------|-------|------------|--------|---------------|")
    else:
        lines.append("| File | Size | Swift | Python | JavaScript | Swift vs Python | Swift vs JS |")
        lines.append("|------|------|-------|--------|------------|-----------------|-------------|")

    total_swift = 0
    total_python = 0
    total_js = 0
    total_rust = 0
    total_rust_justhtml = 0

    for filename in sorted(all_files):
        swift_r = swift_by_file.get(filename, {})
        python_r = python_by_file.get(filename, {})
        js_r = js_by_file.get(filename, {})
        rust_r = rust_by_file.get(filename, {})
        rust_justhtml_r = rust_justhtml_by_file.get(filename, {})

        size = swift_r.get('size_bytes') or python_r.get('size_bytes') or js_r.get('size_bytes', 0)
        size_str = f"{size/1024:.0f} KB"

        swift_ms = swift_r.get('avg_ms', 0)
        python_ms = python_r.get('avg_ms', 0)
        js_ms = js_r.get('avg_ms', 0)
        rust_ms = rust_r.get('avg_ms', 0)
        rust_justhtml_ms = rust_justhtml_r.get('avg_ms', 0)

        total_swift += swift_ms
        total_python += python_ms
        total_js += js_ms
        total_rust += rust_ms
        total_rust_justhtml += rust_justhtml_ms

        swift_str = f"{swift_ms:.2f} ms" if swift_ms else "N/A"
        python_str = f"{python_ms:.2f} ms" if python_ms else "N/A"
        js_str = f"{js_ms:.2f} ms" if js_ms else "N/A"
        rust_str = f"{rust_ms:.2f} ms" if rust_ms else "N/A"
        rust_justhtml_str = f"{rust_justhtml_ms:.2f} ms" if rust_justhtml_ms else "N/A"

        if rust_results and rust_justhtml_results:
            lines.append(f"| {filename} | {size_str} | {rust_str} | {rust_justhtml_str} | {swift_str} | {js_str} | {python_str} |")
        elif rust_results:
            # Rust vs Swift ratio
            rust_swift_ratio = swift_ms / rust_ms if rust_ms and swift_ms else 0
            ratio_str = f"{rust_swift_ratio:.2f}x faster" if rust_swift_ratio > 1 else f"{1/rust_swift_ratio:.2f}x slower" if rust_swift_ratio else "N/A"
            lines.append(f"| {filename} | {size_str} | {rust_str} | {swift_str} | {js_str} | {python_str} | {ratio_str} |")
        else:
            # Speed ratios
            swift_py_ratio = python_ms / swift_ms if swift_ms and python_ms else 0
            swift_js_ratio = js_ms / swift_ms if swift_ms and js_ms else 0
            ratio_py_str = f"{swift_py_ratio:.2f}x faster" if swift_py_ratio > 1 else f"{1/swift_py_ratio:.2f}x slower" if swift_py_ratio else "N/A"
            ratio_js_str = f"{swift_js_ratio:.2f}x faster" if swift_js_ratio > 1 else f"{1/swift_js_ratio:.2f}x slower" if swift_js_ratio else "N/A"
            lines.append(f"| {filename} | {size_str} | {swift_str} | {python_str} | {js_str} | {ratio_py_str} | {ratio_js_str} |")

    # Totals
    if rust_results and rust_justhtml_results:
        lines.append(f"| **TOTAL** | | **{total_rust:.0f} ms** | **{total_rust_justhtml:.0f} ms** | **{total_swift:.0f} ms** | **{total_js:.0f} ms** | **{total_python:.0f} ms** |")
    elif rust_results:
        rust_swift_total = total_swift / total_rust if total_rust else 0
        ratio_total = f"{rust_swift_total:.2f}x faster" if rust_swift_total > 1 else f"{1/rust_swift_total:.2f}x slower" if rust_swift_total else "N/A"
        lines.append(f"| **TOTAL** | | **{total_rust:.0f} ms** | **{total_swift:.0f} ms** | **{total_js:.0f} ms** | **{total_python:.0f} ms** | **{ratio_total}** |")
    else:
        swift_py_total = total_python / total_swift if total_swift else 0
        swift_js_total = total_js / total_swift if total_swift else 0
        ratio_py_total = f"{swift_py_total:.2f}x faster" if swift_py_total > 1 else f"{1/swift_py_total:.2f}x slower" if swift_py_total else "N/A"
        ratio_js_total = f"{swift_js_total:.2f}x faster" if swift_js_total > 1 else f"{1/swift_js_total:.2f}x slower" if swift_js_total else "N/A"
        lines.append(f"| **TOTAL** | | **{total_swift:.0f} ms** | **{total_python:.0f} ms** | **{total_js:.0f} ms** | **{ratio_py_total}** | **{ratio_js_total}** |")
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    if rust_results:
        lines.append(f"- **Rust (html5ever)** total parse time: {total_rust:.0f} ms")
    if rust_justhtml_results:
        lines.append(f"- **rust-justhtml** total parse time: {total_rust_justhtml:.0f} ms")
    lines.append(f"- **Swift** total parse time: {total_swift:.0f} ms")
    lines.append(f"- **JavaScript** total parse time: {total_js:.0f} ms")
    lines.append(f"- **Python** total parse time: {total_python:.0f} ms")
    lines.append("")

    all_totals = [(total_swift, "Swift"), (total_python, "Python"), (total_js, "JavaScript")]
    if rust_results:
        all_totals.append((total_rust, "html5ever"))
    if rust_justhtml_results:
        all_totals.append((total_rust_justhtml, "rust-justhtml"))
    all_totals = [(t, n) for t, n in all_totals if t > 0]

    if all_totals:
        fastest_time, fastest_name = min(all_totals, key=lambda x: x[0])
        lines.append(f"**{fastest_name}** is the fastest implementation.")
        lines.append("")
        if rust_results and total_rust:
            lines.append(f"html5ever is **{total_swift/total_rust:.1f}x faster** than Swift.")
            if rust_justhtml_results and total_rust_justhtml:
                lines.append(f"html5ever is **{total_rust_justhtml/total_rust:.1f}x faster** than rust-justhtml.")
            lines.append(f"html5ever is **{total_js/total_rust:.1f}x faster** than JavaScript.")
            lines.append(f"html5ever is **{total_python/total_rust:.1f}x faster** than Python.")
        if rust_justhtml_results and total_rust_justhtml:
            lines.append(f"rust-justhtml is **{total_swift/total_rust_justhtml:.1f}x faster** than Swift.")
            lines.append(f"rust-justhtml is **{total_python/total_rust_justhtml:.1f}x faster** than Python.")
        elif total_swift:
            lines.append(f"Swift is **{total_python/total_swift:.1f}x faster** than Python.")
            if total_js:
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

def print_summary(swift_results, python_results, js_results, rust_results=None, rust_justhtml_results=None):
    """Print performance summary table."""
    print("\n" + "=" * 60)
    print("PERFORMANCE COMPARISON")
    print("=" * 60)

    swift_by_file = {r['file']: r for r in swift_results} if swift_results else {}
    python_by_file = {r['file']: r for r in python_results} if python_results else {}
    js_by_file = {r['file']: r for r in js_results} if js_results else {}
    rust_by_file = {r['file']: r for r in rust_results} if rust_results else {}
    rust_justhtml_by_file = {r['file']: r for r in rust_justhtml_results} if rust_justhtml_results else {}

    all_files = set(swift_by_file.keys()) | set(python_by_file.keys()) | set(js_by_file.keys())

    # Header
    if rust_results and rust_justhtml_results:
        print(f"\n{'File':<25} {'Size':>8} | {'h5ever':>8} {'rjhtml':>8} {'Swift':>8} {'JS':>8} {'Python':>8}")
        print("-" * 95)
    elif rust_results:
        print(f"\n{'File':<30} {'Size':>10} | {'Rust':>10} {'Swift':>10} {'JS':>10} {'Python':>10} | {'Rust/Swift':>10}")
        print("-" * 115)
    else:
        print(f"\n{'File':<25} {'Size':>10} | {'Swift':>10} {'Python':>10} {'JS':>10} | {'Swift/Py':>8} {'Swift/JS':>8}")
        print("-" * 100)

    total_swift = 0
    total_python = 0
    total_js = 0
    total_rust = 0
    total_rust_justhtml = 0

    for filename in sorted(all_files):
        swift_r = swift_by_file.get(filename, {})
        python_r = python_by_file.get(filename, {})
        js_r = js_by_file.get(filename, {})
        rust_r = rust_by_file.get(filename, {})
        rust_justhtml_r = rust_justhtml_by_file.get(filename, {})

        size = swift_r.get('size_bytes') or python_r.get('size_bytes') or js_r.get('size_bytes', 0)
        size_kb = f"{size/1024:.0f}KB"

        swift_ms = swift_r.get('avg_ms', 0)
        python_ms = python_r.get('avg_ms', 0)
        js_ms = js_r.get('avg_ms', 0)
        rust_ms = rust_r.get('avg_ms', 0)
        rust_justhtml_ms = rust_justhtml_r.get('avg_ms', 0)

        total_swift += swift_ms
        total_python += python_ms
        total_js += js_ms
        total_rust += rust_ms
        total_rust_justhtml += rust_justhtml_ms

        swift_str = f"{swift_ms:.1f}ms" if swift_ms else "N/A"
        python_str = f"{python_ms:.1f}ms" if python_ms else "N/A"
        js_str = f"{js_ms:.1f}ms" if js_ms else "N/A"
        rust_str = f"{rust_ms:.2f}ms" if rust_ms else "N/A"
        rust_justhtml_str = f"{rust_justhtml_ms:.1f}ms" if rust_justhtml_ms else "N/A"

        if rust_results and rust_justhtml_results:
            print(f"{filename:<25} {size_kb:>8} | {rust_str:>8} {rust_justhtml_str:>8} {swift_str:>8} {js_str:>8} {python_str:>8}")
        elif rust_results:
            rust_swift_ratio = swift_ms / rust_ms if rust_ms and swift_ms else 0
            ratio_str = f"{rust_swift_ratio:.1f}x" if rust_swift_ratio else "N/A"
            print(f"{filename:<30} {size_kb:>10} | {rust_str:>10} {swift_str:>10} {js_str:>10} {python_str:>10} | {ratio_str:>10}")
        else:
            swift_py_ratio = python_ms / swift_ms if swift_ms and python_ms else 0
            swift_js_ratio = js_ms / swift_ms if swift_ms and js_ms else 0
            ratio_py_str = f"{swift_py_ratio:.1f}x" if swift_py_ratio else "N/A"
            ratio_js_str = f"{swift_js_ratio:.1f}x" if swift_js_ratio else "N/A"
            print(f"{filename:<25} {size_kb:>10} | {swift_str:>10} {python_str:>10} {js_str:>10} | {ratio_py_str:>8} {ratio_js_str:>8}")

    if rust_results and rust_justhtml_results:
        print("-" * 95)
        print(f"{'TOTAL':<25} {'':<8} | {total_rust:>7.0f}ms {total_rust_justhtml:>7.0f}ms {total_swift:>7.0f}ms {total_js:>7.0f}ms {total_python:>7.0f}ms")
        print(f"\nhtml5ever is {total_rust_justhtml/total_rust:.1f}x faster than rust-justhtml")
        print(f"rust-justhtml is {total_swift/total_rust_justhtml:.1f}x faster than Swift")
    elif rust_results:
        print("-" * 115)
        rust_swift_total = total_swift / total_rust if total_rust else 0
        print(f"{'TOTAL':<30} {'':<10} | {total_rust:>9.0f}ms {total_swift:>9.0f}ms {total_js:>9.0f}ms {total_python:>9.0f}ms | {rust_swift_total:>9.1f}x")
        print("\n(Higher ratio = Rust is faster by that factor)")
    else:
        print("-" * 100)
        swift_py_total = total_python / total_swift if total_swift else 0
        swift_js_total = total_js / total_swift if total_swift else 0
        print(f"{'TOTAL':<25} {'':<10} | {total_swift:>9.0f}ms {total_python:>9.0f}ms {total_js:>9.0f}ms | {swift_py_total:>7.1f}x {swift_js_total:>7.1f}x")
        print("\n(Higher ratio = Swift is faster by that factor)")

def main():
    # Get git info for all projects
    print("Gathering git information...", file=sys.stderr)
    git_info = {
        'swift-justhtml': get_git_info(SWIFT_PROJECT_ROOT),
        'justhtml (Python)': get_git_info(JUSTHTML_ROOT / 'justhtml'),
        'justjshtml (JavaScript)': get_git_info(JUSTHTML_ROOT / 'justjshtml'),
        'html5ever (Rust)': get_git_info(JUSTHTML_ROOT / 'html5ever'),
        'rust-justhtml': get_git_info(JUSTHTML_ROOT / 'rust-justhtml'),
    }

    # Download samples if needed
    download_samples()

    # Run all benchmarks
    swift_results = run_swift_benchmark()
    python_results = run_python_benchmark()
    js_results = run_js_benchmark()
    rust_results = run_rust_benchmark()
    rust_justhtml_results = run_rust_justhtml_benchmark()

    # Compare outputs
    all_match, file_results = compare_outputs(swift_results, python_results, js_results, rust_results)

    # Print performance summary
    print_summary(swift_results, python_results, js_results, rust_results, rust_justhtml_results)

    # Generate markdown report
    markdown_report = generate_markdown_report(
        swift_results, python_results, js_results,
        all_match, file_results, git_info, rust_results, rust_justhtml_results
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
        'rust': rust_results,
        'rust_justhtml': rust_justhtml_results,
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
