# -*- coding: utf-8 -*-
with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _buildGridCard method
idx = content.find('  Widget _buildGridCard(')
if idx == -1:
    print('Method not found')
    exit(1)

method_end = content.find('\n  String _priceText', idx)
method = content[idx:content.find('\n  String _priceText', idx)]

# Replace # comments with // in the method
method = method.replace('# UST: Asset adi + sembol + WatchStar', '// UST: Asset adi + sembol + WatchStar')
method = method.replace('# ORTA: Sparkline (tam genislik)', '// ORTA: Sparkline (tam genislik)')
method = method.replace('# ALT: Fiyat + % Degisim (saga hizali)', '// ALT: Fiyat + % Degisim (saga hizali)')

# Replace in content
content = content[:idx] + method + content[idx + len(method):]

with open('lib/shared/widgets/quote_card.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print('Fixed comments')