#!/usr/bin/env python3
"""
Cross-implementation memory usage comparison.
Measures peak memory usage during HTML parsing for Swift, Python, JavaScript, and Rust.
Generates a markdown report with memory usage results.
"""

import subprocess
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
SAMPLES_DIR = SCRIPT_DIR / "samples"
TEST_FILES_DIR = SCRIPT_DIR / "test_files"
SWIFT_PROJECT_ROOT = SCRIPT_DIR.parent
JUSTHTML_ROOT = SWIFT_PROJECT_ROOT.parent
RUST_BENCHMARK_DIR = SCRIPT_DIR / "rust_benchmark"


def get_git_info(repo_path):
    """Get git commit hash for a repository."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_path,
            capture_output=True,
            text=True
        )
        return result.stdout.strip()[:12] if result.returncode == 0 else "unknown"
    except Exception:
        return "unknown"


def collect_html_files():
    """Collect all HTML files from samples and test_files directories."""
    files = []

    if SAMPLES_DIR.exists():
        for f in SAMPLES_DIR.iterdir():
            if f.suffix == '.html':
                files.append(f)

    if TEST_FILES_DIR.exists():
        for f in TEST_FILES_DIR.iterdir():
            if f.suffix == '.html':
                files.append(f)

    return sorted(files, key=lambda p: p.name)


def measure_memory_linux(cmd, cwd=None):
    """Measure peak memory usage on Linux using /usr/bin/time."""
    try:
        result = subprocess.run(
            ["/usr/bin/time", "-v"] + cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=300
        )

        # Parse "Maximum resident set size (kbytes): XXXX"
        stderr = result.stderr
        match = re.search(r'Maximum resident set size \(kbytes\): (\d+)', stderr)
        if match:
            return int(match.group(1)) * 1024  # Convert KB to bytes
    except Exception as e:
        print(f"Error measuring memory: {e}", file=sys.stderr)

    return None


def measure_memory_macos(cmd, cwd=None):
    """Measure peak memory usage on macOS using /usr/bin/time."""
    try:
        result = subprocess.run(
            ["/usr/bin/time", "-l"] + cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=300
        )

        # Parse "XXXX  maximum resident set size"
        stderr = result.stderr
        match = re.search(r'(\d+)\s+maximum resident set size', stderr)
        if match:
            return int(match.group(1))  # Already in bytes on macOS
    except Exception as e:
        print(f"Error measuring memory: {e}", file=sys.stderr)

    return None


def measure_memory(cmd, cwd=None):
    """Measure peak memory usage using platform-appropriate method."""
    if sys.platform == "darwin":
        return measure_memory_macos(cmd, cwd)
    else:
        return measure_memory_linux(cmd, cwd)


def create_swift_memory_test(filepath):
    """Create a Swift script to parse a file and exit."""
    script = f'''
import Foundation
import JustHTML

let url = URL(fileURLWithPath: "{filepath}")
let html = try! String(contentsOf: url, encoding: .utf8)
let doc = try! JustHTML(html)
_ = doc.root.toTestFormat()
'''
    return script


def create_python_memory_test(filepath):
    """Create a Python script to parse a file and exit."""
    justhtml_path = JUSTHTML_ROOT / "justhtml" / "src"
    script = f'''
import sys
sys.path.insert(0, "{justhtml_path}")
from justhtml import JustHTML, to_test_format

with open("{filepath}", "r", encoding="utf-8") as f:
    html = f.read()

doc = JustHTML(html)
_ = to_test_format(doc.root)
'''
    return script


def create_js_memory_test(filepath):
    """Create a JavaScript script to parse a file and exit."""
    justjshtml_path = JUSTHTML_ROOT / "justjshtml" / "src"
    script = f'''
import {{ readFileSync }} from 'fs';
import {{ JustHTML }} from '{justjshtml_path}/justhtml.js';
import {{ toTestFormat }} from '{justjshtml_path}/serialize.js';

const html = readFileSync('{filepath}', 'utf-8');
const doc = new JustHTML(html);
const _ = toTestFormat(doc.root);
'''
    return script


def measure_swift_memory(filepath):
    """Measure memory usage for Swift implementation."""
    print(f"  Measuring Swift memory for {filepath.name}...", file=sys.stderr)

    # Build release if not already built
    result = subprocess.run(
        ["swift", "build", "-c", "release", "--product", "benchmark"],
        cwd=SWIFT_PROJECT_ROOT,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"    Swift build failed: {result.stderr}", file=sys.stderr)
        return None

    # Create a temporary Swift script for memory measurement
    with tempfile.NamedTemporaryFile(mode='w', suffix='.swift', delete=False) as f:
        f.write(create_swift_memory_test(str(filepath)))
        temp_script = f.name

    try:
        # Run the script and measure memory
        memory = measure_memory(
            ["swift", "-I", str(SWIFT_PROJECT_ROOT / ".build" / "release"),
             "-L", str(SWIFT_PROJECT_ROOT / ".build" / "release"),
             "-lswift-justhtml", temp_script]
        )
        return memory
    except Exception as e:
        print(f"    Error: {e}", file=sys.stderr)
        return None
    finally:
        os.unlink(temp_script)


def measure_swift_memory_simple(filepath):
    """Measure memory for Swift by running a custom benchmark binary."""
    print(f"  Measuring Swift memory for {filepath.name}...", file=sys.stderr)

    # Create a simple Swift executable that parses the file
    temp_dir = Path(tempfile.mkdtemp())
    sources_dir = temp_dir / "Sources" / "MemTest"
    sources_dir.mkdir(parents=True)

    main_swift = sources_dir / "main.swift"
    main_swift.write_text(f'''
import Foundation
import JustHTML

let url = URL(fileURLWithPath: "{filepath}")
let html = try! String(contentsOf: url, encoding: .utf8)
let doc = try! JustHTML(html)
_ = doc.root.toTestFormat()
''')

    package_swift = temp_dir / "Package.swift"
    package_swift.write_text(f'''
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MemTest",
    dependencies: [
        .package(path: "{SWIFT_PROJECT_ROOT}"),
    ],
    targets: [
        .executableTarget(
            name: "MemTest",
            dependencies: [
                .product(name: "swift-justhtml", package: "swift-justhtml"),
            ]
        ),
    ]
)
''')

    try:
        # Build
        result = subprocess.run(
            ["swift", "build", "-c", "release"],
            cwd=temp_dir,
            capture_output=True,
            text=True,
            timeout=120
        )
        if result.returncode != 0:
            print(f"    Swift build failed: {result.stderr}", file=sys.stderr)
            return None

        # Run and measure memory
        binary = temp_dir / ".build" / "release" / "MemTest"
        memory = measure_memory([str(binary)])
        return memory
    except Exception as e:
        print(f"    Error: {e}", file=sys.stderr)
        return None
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)


def measure_python_memory(filepath):
    """Measure memory usage for Python implementation."""
    print(f"  Measuring Python memory for {filepath.name}...", file=sys.stderr)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(create_python_memory_test(str(filepath)))
        temp_script = f.name

    try:
        memory = measure_memory([sys.executable, temp_script])
        return memory
    except Exception as e:
        print(f"    Error: {e}", file=sys.stderr)
        return None
    finally:
        os.unlink(temp_script)


def measure_js_memory(filepath):
    """Measure memory usage for JavaScript implementation."""
    print(f"  Measuring JavaScript memory for {filepath.name}...", file=sys.stderr)

    with tempfile.NamedTemporaryFile(mode='w', suffix='.mjs', delete=False) as f:
        f.write(create_js_memory_test(str(filepath)))
        temp_script = f.name

    try:
        memory = measure_memory(["node", temp_script])
        return memory
    except Exception as e:
        print(f"    Error: {e}", file=sys.stderr)
        return None
    finally:
        os.unlink(temp_script)


def create_rust_memory_test(filepath):
    """Create a Rust source file to parse a single file and exit."""
    html5ever_path = JUSTHTML_ROOT / "html5ever"
    script = f'''
use std::fs;
use html5ever::tendril::TendrilSink;
use html5ever::parse_document;
use markup5ever_rcdom::RcDom;

fn main() {{
    let html = fs::read_to_string("{filepath}").expect("Failed to read file");
    let dom = parse_document(RcDom::default(), Default::default())
        .from_utf8()
        .read_from(&mut html.as_bytes())
        .unwrap();
    // Access something to prevent optimization
    let _ = dom.document.children.borrow().len();
}}
'''
    return script


def measure_rust_memory(filepath):
    """Measure memory usage for Rust (html5ever) implementation."""
    print(f"  Measuring Rust memory for {filepath.name}...", file=sys.stderr)

    if not RUST_BENCHMARK_DIR.exists():
        print("    Rust benchmark not found, skipping...", file=sys.stderr)
        return None

    # Set up cargo environment
    env = os.environ.copy()
    cargo_bin = Path.home() / ".cargo" / "bin"
    if cargo_bin.exists():
        env["PATH"] = str(cargo_bin) + ":" + env.get("PATH", "")

    # Create a temporary Rust project
    temp_dir = Path(tempfile.mkdtemp())
    src_dir = temp_dir / "src"
    src_dir.mkdir(parents=True)

    # Write main.rs
    main_rs = src_dir / "main.rs"
    main_rs.write_text(create_rust_memory_test(str(filepath)))

    # Write Cargo.toml
    html5ever_path = JUSTHTML_ROOT / "html5ever"
    cargo_toml = temp_dir / "Cargo.toml"
    cargo_toml.write_text(f'''
[package]
name = "memtest"
version = "0.1.0"
edition = "2021"

[dependencies]
html5ever = {{ path = "{html5ever_path}/html5ever" }}
markup5ever_rcdom = {{ path = "{html5ever_path}/rcdom" }}

[profile.release]
opt-level = 3
''')

    try:
        # Build
        result = subprocess.run(
            ["cargo", "build", "--release"],
            cwd=temp_dir,
            capture_output=True,
            text=True,
            timeout=120,
            env=env
        )
        if result.returncode != 0:
            print(f"    Rust build failed: {result.stderr}", file=sys.stderr)
            return None

        # Run and measure memory
        binary = temp_dir / "target" / "release" / "memtest"
        memory = measure_memory([str(binary)])
        return memory
    except Exception as e:
        print(f"    Error: {e}", file=sys.stderr)
        return None
    finally:
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)


def format_bytes(n):
    """Format bytes as human-readable string."""
    if n is None:
        return "N/A"
    if n >= 1024 * 1024 * 1024:
        return f"{n / 1024 / 1024 / 1024:.2f} GB"
    elif n >= 1024 * 1024:
        return f"{n / 1024 / 1024:.2f} MB"
    elif n >= 1024:
        return f"{n / 1024:.2f} KB"
    return f"{n} B"


def generate_markdown_report(results, git_info):
    """Generate a markdown report with memory usage results."""
    lines = []

    lines.append("# Memory Usage Comparison")
    lines.append("")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    # Git info
    lines.append("## Repository Versions")
    lines.append("")
    lines.append("| Project | Commit |")
    lines.append("|---------|--------|")
    for name, commit in git_info.items():
        lines.append(f"| {name} | `{commit}` |")
    lines.append("")

    # Check if we have Rust results
    has_rust = any(r.get('rust_memory') for r in results)

    # Memory comparison table
    lines.append("## Peak Memory Usage (RSS)")
    lines.append("")
    if has_rust:
        lines.append("| File | Size | Rust | Swift | JavaScript | Python | Rust vs Swift |")
        lines.append("|------|------|------|-------|------------|--------|---------------|")
    else:
        lines.append("| File | Size | Swift | Python | JavaScript | Swift vs Python | Swift vs JS |")
        lines.append("|------|------|-------|--------|------------|-----------------|-------------|")

    total_swift = 0
    total_python = 0
    total_js = 0
    total_rust = 0
    count = 0

    for r in results:
        size_str = format_bytes(r['size_bytes'])
        swift_str = format_bytes(r['swift_memory'])
        python_str = format_bytes(r['python_memory'])
        js_str = format_bytes(r['js_memory'])
        rust_str = format_bytes(r.get('rust_memory'))

        if r['swift_memory']:
            total_swift += r['swift_memory']
            count += 1
        if r['python_memory']:
            total_python += r['python_memory']
        if r['js_memory']:
            total_js += r['js_memory']
        if r.get('rust_memory'):
            total_rust += r['rust_memory']

        if has_rust:
            # Rust vs Swift ratio
            if r.get('rust_memory') and r['swift_memory']:
                rust_swift_ratio = r['swift_memory'] / r['rust_memory']
                ratio_str = f"{rust_swift_ratio:.2f}x less" if rust_swift_ratio > 1 else f"{1/rust_swift_ratio:.2f}x more"
            else:
                ratio_str = "N/A"
            lines.append(f"| {r['file']} | {size_str} | {rust_str} | {swift_str} | {js_str} | {python_str} | {ratio_str} |")
        else:
            # Memory ratios
            if r['swift_memory'] and r['python_memory']:
                swift_py_ratio = r['python_memory'] / r['swift_memory']
                ratio_py_str = f"{swift_py_ratio:.2f}x less" if swift_py_ratio > 1 else f"{1/swift_py_ratio:.2f}x more"
            else:
                ratio_py_str = "N/A"

            if r['swift_memory'] and r['js_memory']:
                swift_js_ratio = r['js_memory'] / r['swift_memory']
                ratio_js_str = f"{swift_js_ratio:.2f}x less" if swift_js_ratio > 1 else f"{1/swift_js_ratio:.2f}x more"
            else:
                ratio_js_str = "N/A"

            lines.append(f"| {r['file']} | {size_str} | {swift_str} | {python_str} | {js_str} | {ratio_py_str} | {ratio_js_str} |")

    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    if count > 0:
        lines.append(f"Average peak memory usage across {count} files:")
        lines.append("")
        if has_rust and total_rust > 0:
            lines.append(f"- **Rust (html5ever)**: {format_bytes(total_rust // count)}")
        lines.append(f"- **Swift**: {format_bytes(total_swift // count)}")
        lines.append(f"- **JavaScript**: {format_bytes(total_js // count)}")
        lines.append(f"- **Python**: {format_bytes(total_python // count)}")
        lines.append("")

        if has_rust and total_rust > 0:
            lines.append(f"Rust uses **{total_swift / total_rust:.2f}x less memory** than Swift on average.")
            lines.append(f"Rust uses **{total_js / total_rust:.2f}x less memory** than JavaScript on average.")
            lines.append(f"Rust uses **{total_python / total_rust:.2f}x less memory** than Python on average.")
        elif total_swift > 0:
            lines.append(f"Swift uses **{total_python / total_swift:.2f}x less memory** than Python on average.")
            lines.append(f"Swift uses **{total_js / total_swift:.2f}x less memory** than JavaScript on average.")
    lines.append("")

    lines.append("*Note: Memory measurements are peak RSS (Resident Set Size) which includes shared libraries and may vary between runs.*")
    lines.append("")

    return "\n".join(lines)


def main():
    print("=" * 60, file=sys.stderr)
    print("Memory Usage Comparison", file=sys.stderr)
    print("=" * 60, file=sys.stderr)

    # Get git info
    git_info = {
        'swift-justhtml': get_git_info(SWIFT_PROJECT_ROOT),
        'justhtml (Python)': get_git_info(JUSTHTML_ROOT / 'justhtml'),
        'justjshtml (JavaScript)': get_git_info(JUSTHTML_ROOT / 'justjshtml'),
        'html5ever (Rust)': get_git_info(JUSTHTML_ROOT / 'html5ever'),
    }

    # Collect files
    files = collect_html_files()
    if not files:
        print("Error: No HTML files found", file=sys.stderr)
        sys.exit(1)

    print(f"\nFound {len(files)} HTML files to test", file=sys.stderr)

    results = []

    for filepath in files:
        file_size = filepath.stat().st_size
        print(f"\n{filepath.name} ({format_bytes(file_size)})", file=sys.stderr)

        result = {
            'file': filepath.name,
            'size_bytes': file_size,
            'rust_memory': measure_rust_memory(filepath),
            'swift_memory': measure_swift_memory_simple(filepath),
            'python_memory': measure_python_memory(filepath),
            'js_memory': measure_js_memory(filepath),
        }
        results.append(result)

        # Print result
        print(f"    Rust:   {format_bytes(result['rust_memory'])}", file=sys.stderr)
        print(f"    Swift:  {format_bytes(result['swift_memory'])}", file=sys.stderr)
        print(f"    Python: {format_bytes(result['python_memory'])}", file=sys.stderr)
        print(f"    JS:     {format_bytes(result['js_memory'])}", file=sys.stderr)

    # Generate markdown report
    markdown_report = generate_markdown_report(results, git_info)

    # Save report
    report_path = SCRIPT_DIR / "MEMORY_RESULTS.md"
    with open(report_path, 'w') as f:
        f.write(markdown_report)
    print(f"\nReport saved to: {report_path}", file=sys.stderr)

    # Also print to stdout
    print(markdown_report)

    # Save raw results as JSON
    json_path = SCRIPT_DIR / "memory_results.json"
    with open(json_path, 'w') as f:
        json.dump({
            'generated': datetime.now().isoformat(),
            'git_info': git_info,
            'results': results,
        }, f, indent=2)
    print(f"JSON results saved to: {json_path}", file=sys.stderr)

    return 0


if __name__ == '__main__':
    sys.exit(main())
