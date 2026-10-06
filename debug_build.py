# -*- coding: utf-8 -*-
import sys

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the QuoteCard class
idx = content.find('class QuoteCard')
idx2 = content.find('  @override', content.find('class QuoteCard'))
idx3 = content.find('  @override', idx2 + 1)  # Sparkline
idx4 = content.find('  @override', idx3 + 1)  # QuoteCard build

with open('debug_out.txt', 'w', encoding='utf-8') as f:
    f.write('QuoteCard build @override at: ' + str(idx4) + '\n')

# Find the exact start
build_start = content.find('  @override\n  Widget build(BuildContext context) {', 14000)
with open('debug_out.txt', 'a', encoding='utf-8') as f:
    f.write('Build start at: ' + str(build_start) + '\n')

# Find the end of build method (before _priceText)
method_end = content.find('\n  String _priceText', 14000)
with open('debug_out.txt', 'a', encoding='utf-8') as f:
    f.write('Method end at: ' + str(method_end) + '\n')

# Check what's at the start
with open('debug_old.txt', 'w', encoding='utf-8') as f:
    f.write(content[14000:method_end])

# Find the exact build method start
build_idx = content.find('  @override\n  Widget build(BuildContext context) {', 14000)
with open('debug_out.txt', 'a', encoding='utf-8') as f:
    f.write('Build method at: ' + str(build_idx) + '\n')
    f.write('Context: ' + repr(content[build_idx:build_idx+200]) + '\n')