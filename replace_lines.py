# -*- coding: utf-8 -*-
import sys

# Read the full file
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Find the QuoteCard build method (from @override to before _priceText)
start_idx = -1
end_idx = -1
for i, line in enumerate(lines):
    if '  @override\n' in line and i + 1 < len(lines) and 'Widget build(BuildContext context)' in lines[i + 1]:
        if i > 9600:  # After the _BidAskRow class
            start_idx = i
            break

for i in range(len(lines)):
    if i > 9600 and lines[i].strip() == 'String _priceText':
        end_idx = i
        break

if start_idx >= 0 and end_idx >= 0:
    print(f'Found method from line {start_idx} to {end_idx}')
    
    # Read the new build method from file
    with open('new_build.txt', 'r', encoding='utf-8') as f:
        new_build = f.read()
    
    # Replace lines
    new_lines = lines[:start_idx] + new_build.splitlines(keepends=True) + lines[end_idx:]
    
    with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print('SUCCESS: Replaced build method')
else:
    print('Could not find method boundaries')
    print(f'start_idx: {start_idx}, end_idx: {end_idx}')