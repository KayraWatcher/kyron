#!/usr/bin/env python3
"""
Hesapli Altın 15 Dakikalık Gerçek Fiyat Değişimi Testi
Endpoint: https://hesaplialtin.com/api/v1/public-prices
"""

import json
import os
import time
import requests
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

URL = "https://hesaplialtin.com/api/v1/public-prices"
HEADERS = {}
API_KEY = os.getenv("HESAPLI_ALTIN_API_KEY")
if API_KEY:
    HEADERS["Authorization"] = f"Bearer {API_KEY}"

TARGET_SYMBOLS = ["GRAM_ALTIN_TRY", "CEYREK_YENI_TRY", "GUMUS_TRY", "USD_TRY", "EUR_TRY"]
TEST_DURATION = 900  # 15 dakika = 900 saniye
INTERVAL = 5

def main():
    print("="*70)
    print("HESAPLI ALTIN 15M LIVE TEST")
    print("="*70)
    print("Endpoint: https://hesaplialtin.com/api/v1/public-prices")
    print("Semboller: GRAM_ALTIN_TRY, CEYREK_YENI_TRY, GUMUS_TRY, USD_TRY, EUR_TRY")
    print("Interval: 5 saniye")
    print("Süre: 15 dakika (900s)")
    print("="*70)

    prev_data = {}
    requests_count = 0
    http_errors = 0
    timestamp_changes = 0
    
    price_changes = {
        "GRAM_ALTIN_TRY": 0,
        "CEYREK_YENI_TRY": 0,
        "GUMUS_TRY": 0,
        "USD_TRY": 0,
        "EUR_TRY": 0
    }
    
    # Detaylı istatistikler
    stats = {}
    for sym in ["GRAM_ALTIN_TRY", "CEYREK_YENI_TRY", "GUMUS_TRY", "USD_TRY", "EUR_TRY"]:
        stats[sym] = {
            "first_bid": None, "last_bid": None, "min_bid": None, "max_bid": None,
            "first_ask": None, "last_ask": None, "min_ask": None, "max_ask": None,
            "price_changes": 0
        }
    
    timestamp_changes = 0
    prev = {}
    requests_count = 0
    http_errors = 0
    start = time.monotonic()
    end_time = time.monotonic() + 900  # 15 dakika = 900 saniye
    last_updated_at = None

    while time.monotonic() < time.monotonic() + 900:
        try:
            r = requests.get(URL, headers=HEADERS, timeout=10)
            requests_count += 1
            if r.status_code != 200:
                http_errors += 1
                print(f"[HTTP {r.status_code}] {r.text[:100]}")
                time.sleep(5)
                continue

            data = r.json()
            updated = data.get("updatedAt", "unknown")
            items = data.get("kalemler", {})

            # Timestamp değişimi kontrolü
            if last_updated_at is not None and updated != last_updated_at:
                timestamp_changes += 1
                print(f"\n[{datetime.now().strftime('%H:%M:%S')}] TIMESTAMP CHANGED: {last_updated_at} -> {updated}")
            last_updated_at = updated

            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] updatedAt: {updated}")
            
            any_price_change = False
            for sym, item in items.items():
                if sym not in ["GRAM_ALTIN_TRY", "CEYREK_YENI_TRY", "GUMUS_TRY", "USD_TRY", "EUR_TRY"]:
                    continue
                
                alis = item.get("alis")
                satis = item.get("satis")
                guncelleme = item.get("guncelleme")
                piyasa = item.get("piyasa", "")

                print(f"  {sym} | alis={alis} satis={satis} guncelleme={guncelleme} piyasa={piyasa}")

                if sym in prev:
                    prev_alis, prev_satis, prev_guncelleme = prev[sym]
                    price_changed = (alis != prev_alis) or (satis != prev_satis)
                    guncelleme_changed = (guncelleme != prev_guncelleme)
                    
                    if alis != prev_alis or satis != prev_satis:
                        print(f"  [PRICE CHANGE] {sym}")
                        print(f"  ALIS: {prev_alis} -> {alis}")
                        print(f"  SATIS: {prev_satis} -> {satis}")
                        print(f"  UPDATED: {guncelleme}")
                        stats[sym]["price_changes"] += 1
                        price_changes[sym] += 1
                        any_price_change = True
                    else:
                        print(f"  [NO PRICE CHANGE] {sym} (guncelleme changed: {guncelleme_changed})")
                    
                    if guncelleme != prev_guncelleme:
                        timestamp_changes += 1
                    
                    # İstatistikleri güncelle
                    stats[sym]["price_changes"] = stats[sym].get("price_changes", 0) + (1 if (alis != prev_alis or satis != prev_satis) else 0)
                    
                    # Bid/Ask istatistikleri
                    bid = item.get("alis")
                    ask = item.get("satis")
                    if bid is not None:
                        stats[sym]["first_bid"] = stats[sym]["first_bid"] if stats[sym]["first_bid"] is not None else bid
                        stats[sym]["last_bid"] = bid
                        stats[sym]["min_bid"] = min(stats[sym]["min_bid"], bid) if stats[sym]["min_bid"] is not None else bid
                        stats[sym]["max_bid"] = max(stats[sym]["max_bid"], bid) if stats[sym]["max_bid"] is not None else bid
                    
                    if ask is not None:
                        stats[sym]["first_ask"] = stats[sym]["first_ask"] if stats[sym]["first_ask"] is not None else ask
                        stats[sym]["last_ask"] = ask
                        stats[sym]["min_ask"] = min(stats[sym]["min_ask"], ask) if stats[sym]["min_ask"] is not None else ask
                        stats[sym]["max_ask"] = max(stats[sym]["max_ask"], ask) if stats[sym]["max_ask"] is not None else ask

                else:
                    # First time seeing this symbol
                    stats[sym]["first_bid"] = item.get("alis")
                    stats[sym]["last_bid"] = item.get("alis")
                    stats[sym]["min_bid"] = item.get("alis")
                    stats[sym]["max_bid"] = item.get("alis")
                    stats[sym]["first_ask"] = item.get("satis")
                    stats[sym]["last_ask"] = item.get("satis")
                    stats[sym]["min_ask"] = item.get("satis")
                    stats[sym]["max_ask"] = item.get("satis")
                    stats[sym]["price_changes"] = 0

                prev[sym] = (item.get("alis"), item.get("satis"), item.get("guncelleme"))

            if not any((alis != prev.get(sym, (None, None, None))[0] or satis != prev.get(sym, (None, None, None))[1]) 
                       for sym, item in items.items() if sym in ["GRAM_ALTIN_TRY", "CEYREK_YENI_TRY", "GUMUS_TRY", "USD_TRY", "EUR_TRY"]):
                pass  # No price changes this round

            time.sleep(5)

        except Exception as e:
            print(f"Error: {e}")
            time.sleep(5)

    elapsed = int(time.time() - start_time)
    print("\n" + "="*70)
    print("HESAPLI ALTIN 15M LIVE TEST")
    print("="*70)
    print(f"Duration: {int(time.time() - start_time)}s")
    print(f"Requests: {requests_count}")
    print(f"HTTP errors: {http_errors}")
    print(f"Timestamp changes: {timestamp_changes}")

    for sym in ["GRAM_ALTIN_TRY", "CEYREK_YENI_TRY", "GUMUS_TRY", "USD_TRY", "EUR_TRY"]:
        s = stats[sym]
        print(f"\n{sym}")
        print(f"  First: bid={s['first_bid']} ask={s['first_ask']}")
        print(f"  Last:  bid={s['last_bid']} ask={s['last_ask']}")
        print(f"  Range: bid={s['min_bid']}-{s['max_bid']} ask={s['min_ask']}-{s['max_ask']}")
        print(f"  Price changes: {s['price_changes']}")

    print(f"\nTimestamp changes: {timestamp_changes}")

    if sum(stats[s]["price_changes"] for s in stats) > 0:
        print("\nFINAL: REAL_PRICE_CHANGES_DETECTED")
    else:
        print("\nFINAL: TIMESTAMP_ONLY")

    print(f"\nDuration: {int(time.time() - start_time)}s")

if __name__ == "__main__":
    import os
    import time
    import requests
    from datetime import datetime
    from dotenv import load_dotenv
    load_dotenv()

    URL = "https://hesaplialtin.com/api/v1/public-prices"
    HEADERS = {}
    API_KEY = os.getenv("HESAPLI_ALTIN_API_KEY")
    if API_KEY:
        HEADERS["Authorization"] = f"Bearer {API_KEY}"

    main()