#!/usr/bin/env python3
"""Benchmark justhtml (Python) parser on sample files."""

import sys
import os
import time
import json

# Add justhtml to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'justhtml', 'src'))

from justhtml import JustHTML, to_test_format

def benchmark_file(filepath, iterations=10):
    """Benchmark parsing a single file."""
    with open(filepath, 'r', encoding='utf-8') as f:
        html = f.read()

    file_size = len(html.encode('utf-8'))

    # Warmup
    for _ in range(min(3, iterations // 10 + 1)):
        doc = JustHTML(html)

    # Benchmark
    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        doc = JustHTML(html)
        end = time.perf_counter()
        times.append(end - start)

    # Get output for comparison
    output = to_test_format(doc.root)

    avg_time = sum(times) / len(times)
    min_time = min(times)
    max_time = max(times)
    throughput = file_size / avg_time / 1_000_000  # MB/s

    return {
        'file': os.path.basename(filepath),
        'size_bytes': file_size,
        'iterations': iterations,
        'avg_ms': avg_time * 1000,
        'min_ms': min_time * 1000,
        'max_ms': max_time * 1000,
        'throughput_mbs': throughput,
        'output': output
    }

def main():
    samples_dir = os.path.join(os.path.dirname(__file__), 'samples')

    if not os.path.exists(samples_dir):
        print(f"Error: samples directory not found: {samples_dir}", file=sys.stderr)
        sys.exit(1)

    results = []

    for filename in sorted(os.listdir(samples_dir)):
        if not filename.endswith('.html'):
            continue

        filepath = os.path.join(samples_dir, filename)
        file_size = os.path.getsize(filepath)

        # Adjust iterations based on file size
        if file_size > 500_000:
            iterations = 10
        elif file_size > 100_000:
            iterations = 25
        else:
            iterations = 50

        print(f"Benchmarking {filename} ({file_size:,} bytes, {iterations} iterations)...", file=sys.stderr)
        result = benchmark_file(filepath, iterations)
        results.append(result)
        print(f"  Average: {result['avg_ms']:.2f} ms, Throughput: {result['throughput_mbs']:.2f} MB/s", file=sys.stderr)

    # Output JSON to stdout
    print(json.dumps(results, indent=2))

if __name__ == '__main__':
    main()
