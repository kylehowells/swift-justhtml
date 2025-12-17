#!/usr/bin/env python3
"""
Generate a large synthetic HTML file for benchmarking.

This creates a realistic HTML document with:
- Deeply nested elements
- Many attributes
- HTML entities
- Tables
- Lists
- Comments
- Various tag types

Target size: ~20MB
"""

import random
import os

# Words for generating content
WORDS = [
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "I",
    "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
    "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
    "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
    "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
    "performance", "optimization", "benchmark", "testing", "parsing", "html",
    "document", "element", "attribute", "content", "structure", "layout"
]

CLASSES = ["header", "footer", "main", "sidebar", "content", "nav", "article",
           "section", "item", "card", "btn", "link", "text", "title", "desc",
           "primary", "secondary", "highlight", "active", "disabled"]

def random_words(n):
    return " ".join(random.choices(WORDS, k=n))

def random_class():
    return " ".join(random.choices(CLASSES, k=random.randint(1, 3)))

def random_id():
    return f"id-{random.randint(1, 100000)}"

def generate_text(min_words=5, max_words=50):
    """Generate random text with occasional entities."""
    text = random_words(random.randint(min_words, max_words))
    # Add some HTML entities
    if random.random() < 0.2:
        text = text.replace(" the ", " &amp; ")
    if random.random() < 0.1:
        text = text.replace(" to ", " &lt;to&gt; ")
    if random.random() < 0.1:
        text += " &copy; 2025 &mdash; All rights reserved &nbsp;&nbsp;&nbsp;"
    return text

def generate_table(rows, cols):
    """Generate an HTML table."""
    html = ['<table class="data-table">']
    html.append('<thead><tr>')
    for c in range(cols):
        html.append(f'<th>Column {c + 1}</th>')
    html.append('</tr></thead>')
    html.append('<tbody>')
    for r in range(rows):
        html.append('<tr>')
        for c in range(cols):
            html.append(f'<td data-row="{r}" data-col="{c}">{random_words(random.randint(1, 5))}</td>')
        html.append('</tr>')
    html.append('</tbody>')
    html.append('</table>')
    return '\n'.join(html)

def generate_list(items, ordered=False):
    """Generate an HTML list."""
    tag = 'ol' if ordered else 'ul'
    html = [f'<{tag} class="{random_class()}">']
    for i in range(items):
        nested = ""
        if random.random() < 0.1 and items > 3:  # Occasionally nest lists
            nested = generate_list(random.randint(2, 4), random.random() < 0.5)
        html.append(f'<li>{generate_text(3, 15)}{nested}</li>')
    html.append(f'</{tag}>')
    return '\n'.join(html)

def generate_article():
    """Generate an article section."""
    html = [f'<article id="{random_id()}" class="{random_class()}">']
    html.append(f'<h2>{random_words(random.randint(3, 8))}</h2>')

    # Add paragraphs
    for _ in range(random.randint(2, 5)):
        html.append(f'<p class="{random_class()}">{generate_text(20, 100)}</p>')

    # Maybe add a list
    if random.random() < 0.5:
        html.append(generate_list(random.randint(3, 8), random.random() < 0.3))

    # Maybe add a table
    if random.random() < 0.3:
        html.append(generate_table(random.randint(3, 10), random.randint(3, 6)))

    # Add some inline elements
    html.append('<p>')
    html.append(f'This text has <strong>{random_words(3)}</strong> and ')
    html.append(f'<em>{random_words(2)}</em> and ')
    html.append(f'<a href="https://example.com/{random_id()}" title="{random_words(3)}">{random_words(2)}</a> ')
    html.append(f'and <code>{random_words(1)}</code> and ')
    html.append(f'<span class="{random_class()}" data-value="{random.randint(1, 1000)}">{random_words(5)}</span>.')
    html.append('</p>')

    html.append('</article>')
    return '\n'.join(html)

def generate_nav():
    """Generate a navigation section."""
    html = ['<nav class="main-nav">']
    html.append('<ul>')
    for i in range(random.randint(5, 10)):
        html.append(f'<li><a href="/page-{i}" class="{random_class()}">{random_words(random.randint(1, 3))}</a>')
        if random.random() < 0.3:  # Submenu
            html.append('<ul class="submenu">')
            for j in range(random.randint(2, 5)):
                html.append(f'<li><a href="/page-{i}/sub-{j}">{random_words(2)}</a></li>')
            html.append('</ul>')
        html.append('</li>')
    html.append('</ul>')
    html.append('</nav>')
    return '\n'.join(html)

def generate_form():
    """Generate a form."""
    html = [f'<form action="/submit" method="post" id="{random_id()}" class="{random_class()}">']

    for i in range(random.randint(3, 8)):
        field_id = f"field-{random.randint(1, 10000)}"
        html.append('<div class="form-group">')
        html.append(f'<label for="{field_id}">{random_words(random.randint(1, 3))}</label>')

        field_type = random.choice(['text', 'email', 'password', 'number', 'textarea', 'select'])
        if field_type == 'textarea':
            html.append(f'<textarea id="{field_id}" name="{field_id}" rows="4" placeholder="{random_words(3)}"></textarea>')
        elif field_type == 'select':
            html.append(f'<select id="{field_id}" name="{field_id}">')
            for j in range(random.randint(3, 8)):
                html.append(f'<option value="{j}">{random_words(2)}</option>')
            html.append('</select>')
        else:
            html.append(f'<input type="{field_type}" id="{field_id}" name="{field_id}" '
                       f'placeholder="{random_words(2)}" class="{random_class()}">')
        html.append('</div>')

    html.append(f'<button type="submit" class="btn {random_class()}">{random_words(2)}</button>')
    html.append('</form>')
    return '\n'.join(html)

def generate_html(target_size_mb=20):
    """Generate the complete HTML document."""

    html = ['''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="A large synthetic HTML file for benchmarking HTML parsers">
    <meta name="keywords" content="benchmark, html, parser, testing, performance">
    <meta name="author" content="swift-justhtml benchmark generator">
    <title>Large Synthetic HTML Document for Benchmarking</title>
    <link rel="stylesheet" href="/styles/main.css">
    <link rel="stylesheet" href="/styles/components.css">
    <link rel="icon" type="image/png" href="/favicon.png">
</head>
<body>
<!-- Main document structure -->
<div id="wrapper" class="page-wrapper">
''']

    # Header
    html.append('<header id="main-header" class="site-header">')
    html.append(f'<h1>{random_words(5)}</h1>')
    html.append(generate_nav())
    html.append('</header>')

    # Main content
    html.append('<main id="content" class="main-content">')

    target_bytes = target_size_mb * 1024 * 1024
    current_size = sum(len(h) for h in html)
    section_num = 0

    while current_size < target_bytes:
        section_num += 1
        section = [f'<section id="section-{section_num}" class="{random_class()}" data-section="{section_num}">']
        section.append(f'<h2>Section {section_num}: {random_words(random.randint(3, 7))}</h2>')

        # Add comment
        if random.random() < 0.3:
            section.append(f'<!-- Section {section_num} comment: {random_words(10)} -->')

        # Add articles
        for _ in range(random.randint(2, 5)):
            section.append(generate_article())

        # Maybe add a form
        if random.random() < 0.2:
            section.append(generate_form())

        # Maybe add a large table
        if random.random() < 0.15:
            section.append(generate_table(random.randint(20, 50), random.randint(5, 10)))

        section.append('</section>')

        section_html = '\n'.join(section)
        html.append(section_html)
        current_size += len(section_html)

        if section_num % 10 == 0:
            print(f"Generated {section_num} sections, {current_size / 1024 / 1024:.1f} MB")

    html.append('</main>')

    # Footer
    html.append('<footer id="main-footer" class="site-footer">')
    html.append(f'<p>&copy; 2025 {random_words(3)}. All rights reserved.</p>')
    html.append(generate_nav())
    html.append('</footer>')

    html.append('</div>')
    html.append('</body>')
    html.append('</html>')

    return '\n'.join(html)

def main():
    print("Generating large synthetic HTML file...")

    # Set seed for reproducibility
    random.seed(42)

    html = generate_html(target_size_mb=20)

    output_path = os.path.join(os.path.dirname(__file__), 'test_files', 'synthetic.html')
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(html)

    size_mb = os.path.getsize(output_path) / 1024 / 1024
    print(f"\nGenerated: {output_path}")
    print(f"Size: {size_mb:.2f} MB")
    print(f"Lines: {html.count(chr(10)) + 1}")

if __name__ == '__main__':
    main()
