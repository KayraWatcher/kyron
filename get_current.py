import sys

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the QuoteCard build method
build_start = content.find('  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);', 9600)
print('Build start at:', build_start)

method_end = content.find('\n  String _priceText', 9600)
print('Method end at:', method_end)

# Write the current build method to file for inspection
with open('current_build.txt', 'w', encoding='utf-8') as f:
    f.write(content[9659:method_end])
print('Written to current_build.txt')
print('Length:', method_end - 9659)