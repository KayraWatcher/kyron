import sys

with open('lib/shared/widgets/quote_card.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the QuoteCard build method - it's at 9659
start = 9659
end = content.find('\n  String _priceText', 9659)
current = content[start:end]

with open('current_method.txt', 'w', encoding='utf-8') as f:
    f.write(content[9659:end])
print('Written to current_method.txt')
print('Length:', len(content[9659:end]))