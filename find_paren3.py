# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

balance = 0
for i, line in enumerate(lines):
    for c in line:
        if c == '(':
            balance += 1
        elif c == ')':
            balance -= 1
    if balance < 0:
        print(f'Negative balance at line {i+1}: {lines[i].rstrip()}')
        break

print(f'Final balance: {balance}')