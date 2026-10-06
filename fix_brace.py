# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix the extra closing brace
old = '      );\n    }\n  }\n  String _priceText(AssetDescriptor? asset, Quote q) {'
new = '      );\n    }\n  String _priceText(AssetDescriptor? asset, Quote q) {'

if old in content:
    content = content.replace(old, new)
    with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS: Fixed extra brace')
else:
    print('Pattern not found')
    # Try alternative
    if '      );\n    }\n  }\n  String _priceText' in content:
        content = content.replace('      );\n    }\n  }\n  String _priceText', '      );\n    }\n  String _priceText')
        with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
            f.write(content)
        print('SUCCESS: Fixed with alternative pattern')
    else:
        print('Pattern not found')