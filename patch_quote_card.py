# -*- coding: utf-8 -*-
import sys

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find the QuoteCard class and the build method
start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if 'class QuoteCard extends StatelessWidget' in line:
        class_start = i
        break

# Find the build method in QuoteCard
for i in range(class_start, len(lines)):
    if '  @override' in lines[i] and i + 1 < len(lines) and 'Widget build(BuildContext context)' in lines[i + 1]:
        if i > 9000:  # After _BidAskRow class
            start_idx = i
            break

# Find the end of build method (before _priceText)
for i in range(len(lines)):
    if i > 9600 and lines[i].strip().startswith('String _priceText'):
        end_idx = i
        break

print(f'Found build method from line {start_idx} to {end_idx}')

# Read the new build method from file
with open('new_build.txt', 'r', encoding='utf-8') as f:
    new_build = f.read()

# Replace lines
new_lines = lines[:start_idx] + new_build.splitlines(keepends=True) + lines[end_idx:]

with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print('SUCCESS: Replaced build method')