# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the exact old build
idx = content.find('  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);', 9600)
print('Found at:', idx)

if idx >= 0:
    end_idx = content.find('\n  String _priceText', idx)
    old_build = content[idx:content.find('\n  String _priceText', idx)]
    print('Found at:', idx, 'length:', len(content[idx:content.find('\n  String _priceText', idx)]))
    with open('old_build_found.txt', 'w', encoding='utf-8') as f:
        f.write(content[idx:content.find('\n  String _priceText', idx)])
    print('Written to old_build_found.txt')
else:
    print('Not found with standard search')
    idx2 = content.find('Widget build(BuildContext context) {', 9600)
    print('Widget build at:', idx2)
    if idx2 >= 0:
        print(content[idx2:idx2+100])