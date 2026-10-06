# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _buildGridCard method
idx = content.find('  Widget _buildGridCard(')
method_end = content.find('\n  String _priceText', idx)
method = content[idx:content.find('\n  String _priceText', idx)]

# Find all parentheses with line numbers
lines = method.split('\n')
balance = 0
for line_num, line in enumerate(lines):
    for i, c in enumerate(line):
        if c == '(':
            balance += 1
        elif c == ')':
            balance -= 1
    if balance != 0:
        print(f'Line {line_num}: balance={balance} | {line.strip()}')

print('Done')