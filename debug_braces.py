# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _buildGridCard method
idx = content.find('  Widget _buildGridCard(')
if idx == -1:
    print('Method not found')
else:
    method_end = content.find('\n  String _priceText', idx)
    method = content[idx:content.find('\n  String _priceText', idx)]
    
    # Count braces and parentheses
    open_braces = method.count('{')
    close_braces = method.count('}')
    open_parens = method.count('(')
    close_parens = method.count(')')
    
    print(f'Method length: {len(method)}')
    print(f'Braces: {open_braces} open, {close_braces} close, balance: {open_braces - close_braces}')
    print(f'Parens: {open_parens} open, {close_parens} close, balance: {open_parens - close_parens}')
    
    # Also check the whole file
    total_open_braces = content.count('{')
    total_close_braces = content.count('}')
    total_open_parens = content.count('(')
    total_close_parens = content.count(')')
    print(f'Total braces: {total_open_braces} open, {total_close_braces} close')
    print(f'Total parens: {total_open_parens} open, {total_close_parens} close')