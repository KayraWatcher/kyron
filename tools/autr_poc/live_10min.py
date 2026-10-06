#!/usr/bin/env python3
"""
AuTR WebSocket Live Update Test - 10 Minutes
"""

import asyncio
import json
import os
import time
from datetime import datetime

import websockets
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")

SYMBOL_MAP = {93: "USDTRY", 90: "EURTRY", 17: "CEYREK_YENI", 8: "GUMUSTRY"}
TARGET_INDICES = {93, 90, 17, 8}
WS_URL = f"wss://autr.tr/ws/prices?api_key={os.getenv('AUTR_API_KEY')}"
TEST_DURATION = 600


async def run_test() -> dict:
    results = {
        "connection": "FAIL", "init": "FAIL", "test_duration_sec": 0,
        "total_ws_messages": 0, "target_messages": 0, "real_price_updates": 0,
        "duplicate_messages": 0, "usdtry_updates": 0, "eurtry_updates": 0,
        "ceyrek_yeni_updates": 0, "gumustry_updates": 0,
        "first_real_update": None, "last_real_update": None,
        "update_intervals": [], "errors": [], "connected": False, "init": "FAIL"
    }

    start_time = time.monotonic()
    end_time = start_time + 600

    print("="*70)
    print("AuTR Live Update Test - 10 Minutes")
    print("="*70)
    print(f"Target: 93=USDTRY, 90=EURTRY, 17=CEYREK_YENI, 8=GUMUSTRY")
    print(f"Duration: 10 minutes (600s)")
    print("="*70)

    try:
        async with websockets.connect(
            f"wss://autr.tr/ws/prices?api_key={os.getenv('AUTR_API_KEY')}",
            ping_interval=20, ping_timeout=10, close_timeout=5
        ) as ws:
            print(f"[WS] Connected")
            results = {"connection": "OK", "init": "FAIL", "test_duration_sec": 0,
                       "total_ws_messages": 0, "target_messages": 0,
                       "real_price_updates": 0, "duplicate_messages": 0,
                       "usdtry_updates": 0, "eurtry_updates": 0,
                       "ceyrek_yeni_updates": 0, "gumustry_updates": 0,
                       "first_real_update": None, "last_real_update": None,
                       "update_intervals": [], "errors": [], "connected": False, "init": "FAIL"}

            # INIT
            init_msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
            init_data = json.loads(init_msg)
            if init_data.get("type") != "init":
                return {"errors": [f"Expected INIT, got: {init_msg[:200]}"]}

            print("[WS] INIT received")
            last_prices = {}
            last_update_times = {}

            for item in init_data.get("snapshot", []):
                if isinstance(item, list) and len(item) >= 3:
                    parite_idx = int(item[0])
                    alis = float(item[1])
                    satis = float(item[2])
                    if parite_idx in [93, 90, 17, 8]:
                        last_prices[parite_idx] = (float(item[1]), float(item[2]))
                        print(f"[INIT] idx={parite_idx} alis={item[1]} satis={item[2]}")

            print(f"[INIT] Snapshot: {len(init_data.get('snapshot', []))} items")
            start_time = time.monotonic()
            end_time = start_time + 600

            update_count = 0
            duplicate_count = 0
            first_real_update = None
            last_real_update = None
            update_intervals = []
            usdtry_updates = eurtry_updates = ceyrek_yeni_updates = gumustry_updates = 0
            last_prices = {}
            last_update_times = {}

            # Init last_prices from snapshot
            for item in init_data.get("snapshot", []):
                if isinstance(item, list) and len(item) >= 3:
                    parite_idx = int(item[0])
                    alis = float(item[1])
                    satis = float(item[2])
                    if parite_idx in [93, 90, 17, 8]:
                        last_prices[parite_idx] = (float(item[1]), float(item[2]))

            print("[WS] Listening for live updates (10 minutes)...")
            print("-" * 70)

            while time.monotonic() < end_time:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=2.0)
                    data = json.loads(msg)

                    if data.get("type") == "init":
                        print("  [WS] Re-init received")
                        continue

                    if isinstance(msg, list):
                        for update in data:
                            if not isinstance(update, list) or len(update) < 3:
                                continue
                            parite_idx = int(update[0])
                            if parite_idx not in [93, 90, 17, 8]:
                                continue

                            new_alis = float(update[1])
                            new_satis = float(update[2])
                            now_ms = time.monotonic() * 1000

                            if parite_idx in last_prices:
                                old_alis, old_satis = last_prices[parite_idx]

                                if abs(new_alis - old_alis) < 0.001 and abs(new_satis - old_satis) < 0.001:
                                    continue  # duplicate

                                change_alis = new_alis - old_alis
                                change_satis = new_satis - old_satis
                                change_pct = ((new_alis - old_alis) / old_alis * 100) if old_alis else 0

                                prev_time = last_update_times.get(parite_idx)
                                interval_ms = int(time.monotonic() * 1000 - prev_time) if prev_time else None

                                last_prices[parite_idx] = (new_alis, new_satis)
                                last_update_times[parite_idx] = time.monotonic() * 1000

                                symbol = {93: "USDTRY", 90: "EURTRY", 17: "CEYREK_YENI", 8: "GUMUSTRY"}.get(parite_idx, f"IDX_{parite_idx}")
                                change_pct = ((new_alis - old_alis) / old_alis * 100) if old_alis else 0

                                print(f"[UPDATE] {symbol} alis: {old_alis}->{new_alis} satis: {old_satis}->{new_satis} change={change_pct:+.4f}% interval={interval_ms}ms")

                                if interval_ms:
                                    update_intervals.append(interval_ms)

                                if parite_idx == 93: usdtry_updates += 1
                                elif parite_idx == 90: eurtry_updates += 1
                                elif parite_idx == 17: ceyrek_yeni_updates += 1
                                elif parite_idx == 8: gumustry_updates += 1

                        except asyncio.TimeoutError:
                            continue

                    except asyncio.TimeoutError:
                        pass
                    except websockets.exceptions.ConnectionClosed as e:
                        print(f"[WS] Connection closed: code={e.code}")
                    except Exception as e:
                        print(f"[WS] Error: {e}")
                    finally:
                        return {
                            "connection": "OK", "init": "OK", "test_duration_sec": time.monotonic() - start_time,
                            "total_ws_messages": 0, "target_messages": 0, "real_price_updates": 0,
                            "duplicate_messages": 0, "usdtry_updates": 0, "eurtry_updates": 0,
                            "ceyrek_yeni_updates": 0, "gumustry_updates": 0,
                            "first_real_update": None, "last_real_update": None,
                            "update_intervals": [], "errors": [], "connected": True, "init": "OK"
                        }

    except Exception as e:
        return {"errors": [f"Connection error: {e}"], "connection": "FAIL", "init": "FAIL"}

    return {}


async def main():
    import os, asyncio, json
    from datetime import datetime
    import websockets
    from dotenv import load_dotenv
    load_dotenv()

    API_KEY = os.getenv("AUTR_API_KEY")
    if not API_KEY:
        raise ValueError("AUTR_API_KEY not set in .env")

    print("="*70)
    print("AuTR Live Update Test - 10 Minutes")
    print("="*70)
    print(f"Target: 93=USDTRY, 90=EURTRY, 17=CEYREK_YENI, 8=GUMUSTRY")
    print(f"Duration: 10 minutes (600s)")
    print("="*70)

    results = await run_test()

    # Final report
    print("\n" + "="*70)
    print("LIVE UPDATE TEST RESULTS")
    print("="*70)

    print(f"\nConnection: {results.get('connection', 'UNKNOWN')}")
    print(f"INIT: {results.get('init', 'UNKNOWN')}")
    print(f"Test duration: {results.get('test_duration_sec', 0):.1f}s")
    print(f"Total WS messages: {results.get('total_ws_messages', 0)}")
    print(f"Target messages: {results.get('target_messages', 0)}")
    print(f"Real price updates: {results.get('real_price_updates', 0)}")
    print(f"Duplicate messages: {results.get('duplicate_messages', 0)}")
    print(f"USDTRY updates: {results.get('usdtry_updates', 0)}")
    print(f"EURTRY updates: {results.get('eurtry_updates', 0)}")
    print(f"CEYREK_YENI updates: {results.get('ceyrek_yeni_updates', 0)}")
    print(f"GUMUSTRY updates: {results.get('gumustry_updates', 0)}")

    if results.get("first_real_update"):
        print(f"\nFirst real update: {results['first_real_update']}")
    else:
        print("\nFirst real update: NONE")

    if results.get("last_real_update"):
        print(f"Last real update: {results.get('last_real_update')}")
    else:
        print("Last real update: NONE")

    intervals = results.get("update_intervals", [])
    if intervals:
        print(f"\nAverage update interval: {sum(intervals)/len(intervals):.0f}ms")
        print(f"Min/Max interval: {min(intervals)}ms / {max(intervals)}ms")
    else:
        print("\nAverage update interval: N/A (no updates)")

    if results.get("real_price_updates", 0) == 0:
        print("\nNO LIVE PRICE UPDATE OBSERVED")

    # Save results
    filename = f"autr_live_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(filename, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    print(f"\n[SAVED] Results saved to: {filename}")


if __name__ == "__main__":
    import os, asyncio, json
    from datetime import datetime
    import websockets
    from dotenv import load_dotenv
    load_dotenv()
    asyncio.run(main())