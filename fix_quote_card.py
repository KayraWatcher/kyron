# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the QuoteCard class
idx = content.find('class QuoteCard')
idx2 = content.find('  @override', idx)
idx2 = content.find('  @override', idx2 + 1)  # Second @override (Sparkline)
idx3 = content.find('  @override', idx2 + 1)  # Third @override (QuoteCard build)

print('QuoteCard @override at:', idx3)

# Find the end of the build method (before _priceText)
build_start = content.find('  @override\n  Widget build(BuildContext context) {', 14000)
method_end = content.find('\n  String _priceText', build_start)

print('Build method from', build_start, 'to', method_end)
print('Length:', method_end - build_start)

old_build = content[build_start:method_end]
print('OLD BUILD LENGTH:', len(old_build))
print(old_build[:500])

# Write the old build to a file for inspection
with open('old_build.txt', 'w', encoding='utf-8') as f:
    f.write(content[build_start:method_end])
print('Written to old_build.txt')