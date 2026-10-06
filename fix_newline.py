# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the missing newline
content = content.replace('  }String _priceText', '  }\n  String _priceText')

with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Fixed missing newline')