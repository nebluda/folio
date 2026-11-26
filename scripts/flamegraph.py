#!/usr/bin/env python3
"""Render a macOS sample(1) call tree as an SVG flamegraph."""
import argparse
import hashlib
import html
import re
from dataclasses import dataclass, field
from pathlib import Path

THREAD = re.compile(r'^    (\d+) (Thread_.*)$')
FRAME = re.compile(r'^    (\+[ +!:|]*)(\d+) (.*?)(?: \+ [\d,]+.*)?$')


@dataclass
class Frame:
    name: str
    count: int
    children: list = field(default_factory=list)


def parse_threads(path):
    threads = []
    stack = []
    lines = path.read_text().split('Call graph:\n', 1)[1]
    for line in lines.splitlines():
        if line.startswith('Total number in stack'):
            break
        if match := THREAD.match(line):
            count, name = match.groups()
            thread = Frame(name, int(count))
            threads.append(thread)
            stack = [thread]
        elif stack and (match := FRAME.match(line)):
            columns, count, name = match.groups()
            depth = (len(columns) - 2) // 2
            stack = stack[:depth + 1]
            frame = Frame(name, int(count))
            stack[-1].children.append(frame)
            stack.append(frame)
    return threads


def selected_roots(frame, pattern):
    if pattern.search(frame.name):
        yield frame
    else:
        for child in frame.children:
            yield from selected_roots(child, pattern)


def merge(frames):
    merged = {}
    for frame in frames:
        if frame.name not in merged:
            merged[frame.name] = Frame(frame.name, 0)
        group = merged[frame.name]
        group.count += frame.count
        group.children.extend(frame.children)
    return sorted(merged.values(), key=lambda frame: (-frame.count, frame.name))


def write_graph(output, title, source, root):
    width, row, max_depth = 1260, 20, 26
    margin = 12
    height = (max_depth + 1) * row + 70
    scale = (width - 2 * margin) / root.count
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}">',
             f'<rect width="{width}" height="{height}" fill="#fffaf4"/>',
             f'<text x="{margin}" y="26" font-family="system-ui" font-size="19" font-weight="600">{html.escape(title)}</text>',
             f'<text x="{margin}" y="48" font-family="system-ui" font-size="13">{html.escape(source)} · {root.count:,} stack samples · hover for frame counts</text>',
             '<g font-family="monospace" font-size="11">']

    def draw(frame, x, depth):
        span = frame.count * scale
        if span < 1 or depth > max_depth:
            return
        y = height - 10 - (depth + 1) * row
        seed = hashlib.sha256(frame.name.encode()).digest()
        fill = f'hsl({15 + seed[0] % 35}, 82%, {59 + seed[1] % 22}%)'
        tooltip = html.escape(f'{frame.name} · {frame.count:,} samples ({frame.count / root.count:.1%})')
        parts.append(f'<g><title>{tooltip}</title><rect x="{x:.2f}" y="{y}" width="{span:.2f}" height="{row-1}" rx="2" fill="{fill}"/>')
        limit = int((span - 8) / 6.7)
        if limit >= 4:
            label = frame.name if len(frame.name) <= limit else frame.name[:limit - 1] + '…'
            parts.append(f'<text x="{x+4:.2f}" y="{y+13}">{html.escape(label)}</text>')
        parts.append('</g>')
        child_x = x
        for child in merge(frame.children):
            draw(child, child_x, depth + 1)
            child_x += child.count * scale

    draw(root, margin, 0)
    output.write_text('\n'.join(parts + ['</g></svg>']) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('samples', type=Path, nargs='+')
    parser.add_argument('--thread', required=True, help='Thread or dispatch queue name substring')
    parser.add_argument('--root', help='Regex selecting a subtree of the thread')
    parser.add_argument('--title', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    threads = [thread for path in args.samples for thread in parse_threads(path)
               if args.thread in thread.name]
    pattern = re.compile(args.root) if args.root else None
    frames = [frame for thread in threads for frame in
              (selected_roots(thread, pattern) if pattern else thread.children)]
    if not frames:
        parser.error('No matching sample stacks')
    root = Frame(args.thread, sum(frame.count for frame in frames), frames)
    source = 'macOS sample(1) · inclusive stack samples; width includes waiting'
    write_graph(args.output, args.title, source, root)


if __name__ == '__main__':
    main()
