#!/usr/bin/env node
/**
 * Benchmark justjshtml (JavaScript) parser on sample files.
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'fs';
import { join, dirname, basename } from 'path';
import { fileURLToPath } from 'url';
import { performance } from 'perf_hooks';

const __dirname = dirname(fileURLToPath(import.meta.url));

// Import justjshtml
const justjshtmlPath = join(__dirname, '..', '..', 'justjshtml', 'src', 'justhtml.js');
const { JustHTML } = await import(justjshtmlPath);

// Import toTestFormat
const serializePath = join(__dirname, '..', '..', 'justjshtml', 'src', 'serialize.js');
const { toTestFormat } = await import(serializePath);

function benchmarkFile(filepath, iterations = 10) {
    const html = readFileSync(filepath, 'utf-8');
    const fileSize = Buffer.byteLength(html, 'utf-8');

    // Warmup
    const warmupIterations = Math.min(3, Math.floor(iterations / 10) + 1);
    for (let i = 0; i < warmupIterations; i++) {
        new JustHTML(html);
    }

    // Benchmark
    const times = [];
    let doc;
    for (let i = 0; i < iterations; i++) {
        const start = performance.now();
        doc = new JustHTML(html);
        const end = performance.now();
        times.push((end - start) / 1000); // Convert to seconds
    }

    // Get output for comparison
    const output = toTestFormat(doc.root);

    const avgTime = times.reduce((a, b) => a + b, 0) / times.length;
    const minTime = Math.min(...times);
    const maxTime = Math.max(...times);
    const throughput = fileSize / avgTime / 1_000_000; // MB/s

    return {
        file: basename(filepath),
        size_bytes: fileSize,
        iterations: iterations,
        avg_ms: avgTime * 1000,
        min_ms: minTime * 1000,
        max_ms: maxTime * 1000,
        throughput_mbs: throughput,
        output: output
    };
}

function collectHTMLFiles(directory) {
    if (!existsSync(directory)) {
        return [];
    }
    return readdirSync(directory)
        .filter(f => f.endsWith('.html'))
        .map(filename => {
            const filepath = join(directory, filename);
            const fileSize = statSync(filepath).size;
            return { filepath, filename, fileSize };
        });
}

function main() {
    const samplesDir = join(__dirname, 'samples');
    const testFilesDir = join(__dirname, 'test_files');

    if (!existsSync(samplesDir)) {
        console.error(`Error: samples directory not found: ${samplesDir}`);
        process.exit(1);
    }

    // Collect files from samples directory
    let allFiles = collectHTMLFiles(samplesDir);

    // Add files from test_files directory if it exists
    allFiles = allFiles.concat(collectHTMLFiles(testFilesDir));

    // Sort by filename
    allFiles.sort((a, b) => a.filename.localeCompare(b.filename));

    const results = [];

    for (const { filepath, filename, fileSize } of allFiles) {
        // Adjust iterations based on file size
        let iterations;
        if (fileSize > 5_000_000) {
            // Very large files (>5MB) - fewer iterations
            iterations = 3;
        } else if (fileSize > 500_000) {
            iterations = 10;
        } else if (fileSize > 100_000) {
            iterations = 25;
        } else {
            iterations = 50;
        }

        console.error(`Benchmarking ${filename} (${fileSize.toLocaleString()} bytes, ${iterations} iterations)...`);
        const result = benchmarkFile(filepath, iterations);
        results.push(result);
        console.error(`  Average: ${result.avg_ms.toFixed(2)} ms, Throughput: ${result.throughput_mbs.toFixed(2)} MB/s`);
    }

    // Output JSON to stdout
    console.log(JSON.stringify(results, null, 2));
}

main();
