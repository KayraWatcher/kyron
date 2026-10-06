#!/usr/bin/env python3
"""
Kapalı Çarşı API Test - 10 Minutes
Endpoint: https://kapalicarsi.apiluna.org/
"""

import asyncio
import time
import aiohttp
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

URL = "https://kapalicarsi.apiluna.org/"
TEST_DURATION = 600
TARGET_CODES = {"ALTIN", "CEYREK_YENI", "GUMUS", "USD", "EUR"}

async def main():
    print("="*60)
    print("Kapali Carsi API Test - 10 Minutes")
    print("="*60)
    print(f"Endpoint: {URL}")
    print(f"Targets: {', '.join(TARGET_CODES)}")
    print(f"Duration: {TEST_DURATION}s")
    print("="*60)

    stats = {}
    for sym in TARGET_CODES:
        stats[sym] = {
            "first_bid": None, "last_bid": None, "min_bid": None, "max_bid": None,
            "first_ask": None, "last_ask": None, "min_ask": None, "max_ask": None, "price_changes": 0
        }

    prev_data = {}
    prev_tarih = None
    timestamp_changes = 0
    price_changes_total = 0
    requests_count = 0
    http_errors = 0

    start_time = time.monotonic()
    end_time = start_time + TEST_DURATION

    async with aiohttp.ClientSession() as session:
        while time.monotonic() < end_time:
            try:
                async with session.get(URL, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                    requests_count += 1
                    if resp.status != 200:
                        text = await resp.text()
                        print(f"[HTTP {resp.status}] {text[:100]}")
                        http_errors += 1
                        await asyncio.sleep(5)
                        continue

                    data = await resp.json()
                    print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Response received")

                    if isinstance(data, list):
                        for item in data:
                            code = item.get("code")
                            alis = item.get("alis")
                            satis = item.get("satis")
                            tarih = item.get("tarih")

                            if alis is None or satis is None or code not in TARGET_CODES:
                                continue

                            print(f"  {code} | alis={alis} satis={satis} tarih={tarih}")

                            if code in prev_data:
                                prev_alis, prev_satis = prev_data[code]
                                if alis != prev_alis or satis != prev_satis:
                                    print(f"  [PRICE CHANGE] {code}")
                                    print(f"  ALIS: {prev_alis} -> {alis}")
                                    print(f"  SATIS: {prev_satis} -> {satis}")
                                    print(f"  TARIH: {item.get('tarih', 'N/A')}")
                                    price_changes_total += 1
                                    stats[code]["price_changes"] += 1

                            if tarih != prev_tarih:
                                timestamp_changes += 1

                            # Update stats
                            bid = item.get("alis")
                            ask = item.get("satis")
                            if bid is not None:
                                if stats[code]["first_bid"] is None:
                                    stats[code]["first_bid"] = bid
                                stats[code]["last_bid"] = bid
                                stats[code]["min_bid"] = min(stats[code]["min_bid"], bid) if stats[code]["min_bid"] is not None else bid
                                stats[code]["max_bid"] = max(stats[code]["max_bid"], bid) if stats[code]["max_bid"] is not None else bid

                            if ask is not None:
                                if stats[code]["first_ask"] is None:
                                    stats[code]["first_ask"] = ask
                                stats[code]["last_ask"] = ask
                                stats[code]["min_ask"] = min(stats[code]["min_ask"], ask) if stats[code]["min_ask"] is not None else ask
                                stats[code]["max_ask"] = max(stats[code]["max_ask"], ask) if stats[code]["max_ask"] is not None else ask

                            prev_data[code] = (alis, satis)

                await asyncio.sleep(5)

            except Exception as e:
                print(f"Error: {e}")
                await asyncio.sleep(5)
                continue

    print("\n" + "="*60)
    print("KAPALI CARI 10M LIVE TEST")
    print("="*60)
    print(f"Duration: {int(time.monotonic() - start_time)}s")
    print(f"Requests: {requests_count}")
    print(f"HTTP errors: {http_errors}")
    print(f"Timestamp changes: {timestamp_changes}")
    print(f"Real price changes: {price_changes_total}")
    print("")
    for sym in TARGET_CODES:
        s = stats[sym]
        print(f"\n{sym}")
        print(f"  First: bid={s['first_bid']} ask={s['first_ask']}")
        print(f"  Last:  bid={s['last_bid']} ask={s['last_ask']}")
        print(f"  Range: bid={s['min_bid']}-{s['max_bid']} ask={s['min_ask']}-{s['max_ask']}")
        print(f"  Price changes: {s['price_changes']}")
    print(f"\nTimestamp changes: {timestamp_changes}")
    print("REAL PRICE CHANGES DETECTED" if price_changes_total > 0 else "TIMESTAMP_ONLY")

if __name__ == "__main__":
    asyncio.run(main())