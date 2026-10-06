#!/usr/bin/env python3
"""
Hesapli Altın API Test - 60 seconds
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
TEST_DURATION = 60

def main():
    print("="*60)
    print("Hesapli Altin API Test - 60 seconds")
    print("="*60)

    prev = {}
    requests_count = 0
    http_errors = 0
    changes = {s: 0 for s in ["GRAM_ALTIN_TRY", "CEYREK_YENI_TRY", "GUMUS_TRY", "USD_TRY", "EUR_TRY"]}
    start = time.monotonic()
    end_time = time.monotonic() + 60

    while time.monotonic() < time.monotonic() + 60:
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

            print(f"\n[{datetime.now().strftime('%H:%M:%S')}] updatedAt: {updated}")
            
            any_changed = False
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
                    if alis != prev_alis or satis != prev_satis or guncelleme != prev_guncelleme:
                        print(f"  [CHANGED] {sym} alis={prev_alis}->{alis} satis={prev_satis}->{satis} guncelleme={prev_guncelleme}->{guncelleme}")
                        changes[sym] += 1
                        any_changed = True
                else:
                    print(f"  [FIRST SEEN] {sym}")
                    any_changed = True
                
                prev[sym] = (item.get("alis"), item.get("satis"), item.get("guncelleme"))

            if not any_changed:
                print("[UNCHANGED]")
            
            time.sleep(5)

        except Exception as e:
            print(f"Error: {e}")
            time.sleep(5)

    elapsed = int(time.time() - start_time)
    print("\n" + "="*50)
    print("SUMMARY")
    print("="*50)
    print(f"Connection: OK")
    print(f"Requests: {requests_count}")
    print(f"HTTP errors: {http_errors}")
    print(f"Gram changes: {changes['GRAM_ALTIN_TRY']}")
    print(f"Quarter changes: {changes['CEYREK_YENI_TRY']}")
    print(f"Silver changes: {changes['GUMUS_TRY']}")
    print(f"USDTRY changes: {changes['USD_TRY']}")
    print(f"EURTRY changes: {changes['EUR_TRY']}")
    print(f"Last updatedAt: {updated}")
    print(f"Duration: {int(time.time() - start_time)}s")

if __name__ == "__main__":
    import os
    import time
    import requests
    from datetime import datetime
    from dotenv import load_dotenv
    load_dotenv()
    main()