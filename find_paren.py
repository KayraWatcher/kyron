# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _buildGridCard method
idx = content.find('  Widget _buildGridCard(')
method_end = content.find('\n  String _priceText', idx)
method = content[idx:content.find('\n  String _priceText', idx)]

# Find unmatched parentheses by tracking balance
balance = 0
for i, c in enumerate(method):
    if c == '(':
        balance += 1
    elif c == ')':
        balance -= 1
    if balance < 0:
        print(f'Negative balance at pos {idx+i}: {method[max(0,i-30):i+30]}')
        break

# Find where balance becomes positive at the end
balance = 0
for i, c in enumerate(method):
    if c == '(':
        balance += 1
    elif c == ')':
        balance -= 1
    if balance == 1 and i > len(method) - 100:
        print(f'Final unmatched at pos {idx+i}: {method[max(0,i-30):i+30]}')

print('Done')