// NEWS ENCODING DEBUG - Capture raw Anadolu Agency RSS response

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

void main() {
  group('NEWS ENCODING DEBUG - Anadolu Agency RSS', () {
    const aaEkonomiUrl = 'https://www.aa.com.tr/tr/rss/default?cat=ekonomi';

    test('Fetch RAW bytes and analyze encoding', () async {
      final client = http.Client();
      
      try {
        print('Fetching: $aaEkonomiUrl');
        final response = await client.get(
          Uri.parse(aaEkonomiUrl),
          headers: const {
            'Accept': 'application/rss+xml, application/xml, text/xml',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ).timeout(const Duration(seconds: 15));
        
        print('Status: ${response.statusCode}');
        print('Content-Type: ${response.headers['content-type']}');
        print('Content-Length: ${response.headers['content-length']}');
        print('Date: ${response.headers['date']}');
        
        // Analyze raw bytes
        final bytes = response.bodyBytes;
        print('Total bytes: ${bytes.length}');
        
        // Check for BOM
        if (bytes.length >= 3) {
          final bom = bytes.sublist(0, 3);
          print('First 3 bytes (BOM check): ${bom.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          if (bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF) {
            print('UTF-8 BOM detected');
          } else if (bom[0] == 0xFF && bom[1] == 0xFE) {
            print('UTF-16 LE BOM detected');
          } else if (bom[0] == 0xFE && bom[1] == 0xFF) {
            print('UTF-16 BE BOM detected');
          } else {
            print('No BOM detected');
          }
        }
        
        // First 200 chars (lossy UTF-8 decode)
        final first200 = utf8.decode(bytes.take(200).toList(), allowMalformed: true);
        print('\nFirst 200 chars (lossy UTF-8 decode):');
        print(first200);
        
        // Search for encoding declaration - simple string search
        if (first200.contains('encoding=')) {
          print('\nFound "encoding=" in XML declaration');
        } else {
          print('\nNo "encoding=" found in first 200 chars');
        }
        
        // Try different decodings
        print('\n=== DECODING TESTS ===');
        
        // 1. UTF-8 (strict)
        try {
          final utf8Result = utf8.decode(bytes, allowMalformed: false);
          print('UTF-8 (strict): OK, length=${utf8Result.length}');
          print('First 300: ${utf8Result.substring(0, 300)}');
        } catch (e) {
          print('UTF-8 (strict): FAILED - $e');
        }
        
        // 2. UTF-8 lossy
        final utf8Lossy = utf8.decode(bytes, allowMalformed: true);
        print('UTF-8 (lossy): OK, length=${utf8Lossy.length}');
        print('First 300: ${utf8Lossy.substring(0, 300)}');
        
        // 3. Latin-1 (ISO-8859-1)
        final latin1Decoded = latin1.decode(bytes, allowInvalid: true);
        print('Latin-1: OK, length=${latin1Decoded.length}');
        print('First 300: ${latin1Decoded.substring(0, 300)}');
        
        // Try to parse as XML with different encodings
        print('\n=== XML PARSING TESTS ===');
        
        // Parse with UTF-8 (lossy)
        try {
          final doc = XmlDocument.parse(utf8Lossy);
          final items = doc.findAllElements('item');
          print('UTF-8 lossy parse: ${items.length} items found');
          if (items.isNotEmpty) {
            final firstItem = items.first;
            final title = firstItem.findElements('title').firstOrNull?.innerText ?? 'NO TITLE';
            print('First item title: "$title"');
            
            // Check for Turkish characters
            final turkishChars = 'ğüşıöçĞÜŞİÖÇ';
            for (final c in turkishChars.split('')) {
              if (title.contains(c)) {
                print('  Found Turkish char: $c');
              }
            }
            
            // Check for mojibake patterns
            if (title.contains('A°') || title.contains('A+m') || title.contains('A§') || title.contains('A¢')) {
              print('  MOJIBAKE DETECTED in title!');
            }
          }
        } catch (e) {
          print('UTF-8 lossy parse ERROR: $e');
        }
        
        // Parse with Latin-1
        try {
          final doc = XmlDocument.parse(latin1Decoded);
          final items = doc.findAllElements('item');
          print('Latin-1 parse: ${items.length} items found');
          if (items.isNotEmpty) {
            final firstItem = items.first;
            final title = firstItem.findElements('title').firstOrNull?.innerText ?? 'NO TITLE';
            print('First item title: "$title"');
          }
        } catch (e) {
          print('Latin-1 parse ERROR: $e');
        }
        
        // Save raw bytes for inspection
        print('\n=== RAW BYTES (first 500) ===');
        final hexDump = bytes.take(500).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        print(hexDump);
        
      } finally {
        client.close();
      }
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}