import sys

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Get current build method
start = 14118
end = content.find('\n  String _priceText', 14118)
current = content[14118:content.find('\n  String _priceText', 14118)]

with open('current_method.txt', 'w', encoding='utf-8') as f:
    f.write(content[14118:content.find('\n  String _priceText', 14118)])
print('Written to current_method.txt')
print('Length:', len(content[14118:content.find('\n  String _priceText', 14118)]))