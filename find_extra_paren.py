# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the extra opening parenthesis
balance = 0
for i, c in enumerate(content):
    if c == '(':
        balance += 1
    elif c == ')':
        balance -= 1
    if balance > 1:
        print(f'Balance > 1 at pos {i}: {content[max(0,i-50):i+50]}')
        break

# Find where balance never returns to 0
balance = 0
for i, c in enumerate(content):
    if c == '(':
        balance += 1
    elif c == ')':
        balance -= 1
    if balance == 1 and i > 1000:
        # Check if this is the first time balance becomes 1 after being 0
        pass

# Find where balance first becomes 1 and never returns to 0
balance = 0
first_one = -1
for i, c in enumerate(content):
    if c == '(':
        balance += 1
    elif c == ')':
        balance -= 1
    if balance == 1 and first_one == -1:
        first_one = i
        print(f'First balance=1 at pos {i}: {content[max(0,i-30):i+30]}')
    if balance == 0 and first_one != -1:
        print(f'Balance returned to 0 at pos {i}: {content[max(0,i-30):i+30]}')
        break