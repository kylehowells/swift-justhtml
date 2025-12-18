// Benchmark for html5ever - outputs JSON for comparison with other implementations

use std::fs;
use std::iter;
use std::path::Path;
use std::time::Instant;

use html5ever::tendril::TendrilSink;
use html5ever::parse_document;
use markup5ever_rcdom::{Handle, NodeData, RcDom};
use serde::Serialize;

#[derive(Serialize)]
struct BenchmarkResult {
    file: String,
    size_bytes: usize,
    iterations: usize,
    avg_ms: f64,
    min_ms: f64,
    max_ms: f64,
    throughput_mbs: f64,
    output: String,
}

/// Serialize DOM to html5lib test format
fn serialize_to_test_format(buf: &mut String, indent: usize, handle: &Handle) {
    buf.push('|');
    buf.extend(iter::repeat_n(" ", indent));

    match &handle.data {
        NodeData::Document => {
            // Don't output anything for document node, just recurse into children
            for child in handle.children.borrow().iter() {
                serialize_to_test_format(buf, indent, child);
            }
            return;
        }

        NodeData::Doctype {
            name,
            public_id,
            system_id,
        } => {
            buf.push_str("<!DOCTYPE ");
            buf.push_str(name);
            if !public_id.is_empty() || !system_id.is_empty() {
                buf.push_str(&format!(" \"{}\" \"{}\"", public_id, system_id));
            }
            buf.push_str(">\n");
        }

        NodeData::Text { contents } => {
            buf.push('"');
            buf.push_str(&contents.borrow());
            buf.push_str("\"\n");
        }

        NodeData::Comment { contents } => {
            buf.push_str("<!-- ");
            buf.push_str(contents);
            buf.push_str(" -->\n");
        }

        NodeData::Element { name, attrs, template_contents, .. } => {
            buf.push('<');
            match &name.ns {
                ns if *ns == html5ever::ns!(svg) => buf.push_str("svg "),
                ns if *ns == html5ever::ns!(mathml) => buf.push_str("math "),
                _ => (),
            }
            buf.push_str(&name.local);
            buf.push_str(">\n");

            let mut attrs_vec: Vec<_> = attrs.borrow().clone();
            attrs_vec.sort_by(|x, y| x.name.local.cmp(&y.name.local));

            for attr in attrs_vec.iter() {
                buf.push('|');
                buf.extend(iter::repeat_n(" ", indent + 2));
                match &attr.name.ns {
                    ns if *ns == html5ever::ns!(xlink) => buf.push_str("xlink "),
                    ns if *ns == html5ever::ns!(xml) => buf.push_str("xml "),
                    ns if *ns == html5ever::ns!(xmlns) => buf.push_str("xmlns "),
                    _ => (),
                }
                buf.push_str(&format!("{}=\"{}\"\n", attr.name.local, attr.value));
            }

            // Recurse into children
            for child in handle.children.borrow().iter() {
                serialize_to_test_format(buf, indent + 2, child);
            }

            // Handle template contents
            if let Some(ref content) = &*template_contents.borrow() {
                buf.push('|');
                buf.extend(iter::repeat_n(" ", indent + 2));
                buf.push_str("content\n");
                for child in content.children.borrow().iter() {
                    serialize_to_test_format(buf, indent + 4, child);
                }
            }
            return; // Already handled children
        }

        NodeData::ProcessingInstruction { .. } => {}
    }

    // Recurse into children (for non-element nodes)
    for child in handle.children.borrow().iter() {
        serialize_to_test_format(buf, indent + 2, child);
    }
}

fn dom_to_test_format(dom: &RcDom) -> String {
    let mut result = String::new();
    for child in dom.document.children.borrow().iter() {
        serialize_to_test_format(&mut result, 1, child);
    }
    // Remove trailing newline if present
    if result.ends_with('\n') {
        result.pop();
    }
    result
}

fn benchmark_file(filepath: &Path, iterations: usize) -> BenchmarkResult {
    let html = fs::read_to_string(filepath).expect("Failed to read file");
    let file_size = html.len();

    // Warmup
    let warmup_iterations = std::cmp::min(3, iterations / 10 + 1);
    for _ in 0..warmup_iterations {
        let _ = parse_document(RcDom::default(), Default::default())
            .from_utf8()
            .read_from(&mut html.as_bytes())
            .unwrap();
    }

    // Benchmark
    let mut times = Vec::with_capacity(iterations);
    let mut dom = None;

    for _ in 0..iterations {
        let start = Instant::now();
        dom = Some(
            parse_document(RcDom::default(), Default::default())
                .from_utf8()
                .read_from(&mut html.as_bytes())
                .unwrap(),
        );
        let elapsed = start.elapsed();
        times.push(elapsed.as_secs_f64());
    }

    // Get output for comparison
    let output = dom.map(|d| dom_to_test_format(&d)).unwrap_or_default();

    let avg_time: f64 = times.iter().sum::<f64>() / times.len() as f64;
    let min_time: f64 = times.iter().cloned().fold(f64::INFINITY, f64::min);
    let max_time: f64 = times.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let throughput = file_size as f64 / avg_time / 1_000_000.0; // MB/s

    BenchmarkResult {
        file: filepath.file_name().unwrap().to_string_lossy().to_string(),
        size_bytes: file_size,
        iterations,
        avg_ms: avg_time * 1000.0,
        min_ms: min_time * 1000.0,
        max_ms: max_time * 1000.0,
        throughput_mbs: throughput,
        output,
    }
}

fn collect_html_files(directory: &Path) -> Vec<(std::path::PathBuf, String, usize)> {
    if !directory.exists() {
        return vec![];
    }

    let mut files = vec![];
    if let Ok(entries) = fs::read_dir(directory) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "html").unwrap_or(false) {
                if let Ok(metadata) = fs::metadata(&path) {
                    let filename = path.file_name().unwrap().to_string_lossy().to_string();
                    files.push((path, filename, metadata.len() as usize));
                }
            }
        }
    }
    files
}

fn main() {
    let script_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let samples_dir = script_dir.join("../samples");
    let test_files_dir = script_dir.join("../test_files");

    if !samples_dir.exists() {
        eprintln!("Error: samples directory not found: {:?}", samples_dir);
        std::process::exit(1);
    }

    let mut all_files = collect_html_files(&samples_dir);
    all_files.extend(collect_html_files(&test_files_dir));

    // Sort by filename
    all_files.sort_by(|a, b| a.1.cmp(&b.1));

    let mut results = Vec::new();

    for (filepath, filename, file_size) in all_files {
        // Adjust iterations based on file size
        let iterations = if file_size > 5_000_000 {
            3
        } else if file_size > 500_000 {
            10
        } else if file_size > 100_000 {
            25
        } else {
            50
        };

        eprintln!(
            "Benchmarking {} ({} bytes, {} iterations)...",
            filename, file_size, iterations
        );
        let result = benchmark_file(&filepath, iterations);
        eprintln!(
            "  Average: {:.2} ms, Throughput: {:.2} MB/s",
            result.avg_ms, result.throughput_mbs
        );
        results.push(result);
    }

    // Output JSON to stdout
    let json = serde_json::to_string_pretty(&results).expect("Failed to serialize results");
    println!("{}", json);
}
