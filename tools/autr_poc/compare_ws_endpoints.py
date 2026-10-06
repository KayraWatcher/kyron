#!/usr/bin/env python3
"""
AuTR WebSocket Endpoint Comparison Test
Compares /ws/prices (current) vs /ws/live (documented live endpoint)
Tests both endpoints with the same API key and mapping
"""

import asyncio
import json
import os
import time
from datetime import datetime
from typing import Dict, List, Optional

import websockets
import aiohttp
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")

# Verified mappings from previous tests
KNOWN_MAPPING = {
    93: "USDTRY",
    90: "EURTRY", 
    17: "CEYREK_YENI",
    8: "GUMUSTRY",
}

TARGET_INDICES = {93, 90, 17, 8}
TARGET_SYMBOLS = {"USDTRY", "EURTRY", "CEYREK_YENI", "GUMUSTRY"}

# REST reference prices for comparison
REST_PRICES = {
    "USDTRY": {"alis": 49.11, "satis": 49.175},
    "EURTRY": {"alis": 55.151, "satis": 55.298},
    "CEYREK_YENI": {"alis": 10714, "satis": 10782},
    "GUMUSTRY": {"alis": 88.95, "satis": 97.06},
    "GRAMALTIN": {"alis": 6535.26, "satis": 6615.48},
}

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")

WS_PRICES_URL = f"wss://autr.tr/ws/prices?api_key={API_KEY}"
WS_LIVE_URL = f"wss://autr.tr/ws/live?api_key={API_KEY}"

RESULTS_FILE = f"autr_ws_endpoint_comparison_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"


async def test_endpoint(ws_url: str, endpoint_name: str, test_duration: int = 30) -> dict:
    """Test a WebSocket endpoint and return detailed results"""
    
    print(f"\n{'='*70}")
    print(f"TESTING: {endpoint_name} ({ws_url})")
    print(f"Duration: {duration}s")
    print("="*70)
    
    results = {
        "endpoint_name": endpoint_name,
        "ws_url": ws_url,
        "connected": False,
        "init_received": False,
        "init_snapshot_count": 0,
        "init_snapshot_raw": None,
        "target_mappings": {},
        "updates": [],
        "update_count": 0,
        "update_intervals_ms": [],
        "errors": [],
        "connected": False,
        "clean_shutdown": False,
        "test_duration_sec": duration,
    }
    
    try:
        async with websockets.connect(
            ws_url,
            ping_interval=20,
            ping_timeout=10,
            close_timeout=5
        ) as ws:
            print(f"[WS] Connected to {ws_url}")
            results["connected"] = True
            
            # Receive INIT message
            init_msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
            init_data = json.loads(init_msg)
            
            if init_data.get("type") != "init":
                results["errors"].append(f"Expected INIT, got: {init_msg[:200]}")
                return results
            
            print(f"[WS] INIT received")
            results["init_received"] = True
            results["init_snapshot_raw"] = init_data
            snapshot = init_data.get("snapshot", [])
            results["init_snapshot_count"] = len(snapshot)
            
            print(f"[INIT] Snapshot items: {len(snapshot)}")
            
            # Process INIT snapshot - build index mapping and check target symbols
            target_found = {}
            for item in init_data.get("snapshot", []):
                if isinstance(item, list) and len(item) >= 3:
                    parite_idx = int(item[0])
                    alis = float(item[1])
                    satis = float(item[2])
                    
                    if parite_idx in [93, 90, 17, 8]:
                        results["target_mappings"][parite_idx] = {
                            "alis": alis,
                            "satis": satis,
                            "raw": [parite_idx, alis, satis]
                        }
                        
                        # Compare with REST if available
                        symbol = None
                        for sym, idx in [(93, "USDTRY"), (90, "EURTRY"), (17, "CEYREK_YENI"), (8, "GUMUSTRY")]:
                            if parite_idx == sym:
                                symbol = idx
                                break
                        if symbol in REST_PRICES:
                            rest_p = REST_PRICES[symbol]
                            ws_alis = float(item[1])
                            ws_satis = float(item[2])
                            diff_alis = abs(rest_p["alis"] - ws_alis) / rest_p["alis"] * 100
                            diff_satis = abs(rest_p["satis"] - ws_satis) / rest_p["satis"] * 100
                            print(f"  [INIT] idx={parite_idx} symbol={symbol} WS:{ws_alis}/{ws_satis} REST:{rest_p['alis']}/{rest_p['satis']} diff_alis={diff_alis:.2f}% diff_satis={diff_satis:.2f}%")
                        else:
                            print(f"  [INIT] idx={parite_idx} alis={item[1]} satis={item[2]}")
            
            print(f"[WS] Connected to {ws_url}")
            print(f"[INIT] Snapshot items: {len(init_data.get('snapshot', []))}")
            
            # Listen for live updates
            print(f"\n[WS] Listening for live updates ({duration}s)...")
            start_time = time.monotonic()
            last_update_time = {}
            update_count = 0
            
            try:
                async for message in ws:
                    elapsed = time.monotonic() - start_time
                    if elapsed > duration:
                        break
                    
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=2.0)
                        data = json.loads(message)
                        
                        if data.get("type") == "init":
                            print(f"  [WS] Re-init received (reconnect?)")
                            continue
                        
                        if isinstance(msg, list):
                            for update in data:
                                if not isinstance(update, list) or len(update) < 3:
                                    continue
                                idx, alis, satis = update[0], update[1], update[2]
                                if int(idx) in [93, 90, 17, 8]:
                                    now_ms = time.monotonic() * 1000
                                    prev = last_update_time.get(int(idx), (None, None))
                                    
                                    if prev[0] is not None:
                                        interval_ms = int(time.monotonic() * 1000 - prev[0])
                                        change_alis = float(update[1]) - prev[1] if prev[1] is not None else 0
                                        change_satis = float(update[2]) - prev[2] if prev[2] is not None else 0
                                        symbol = None
                                        for s, i in [(93, "USDTRY"), (90, "EURTRY"), (17, "CEYREK_YENI"), (8, "GUMUSTRY")]:
                                            if int(idx) == s:
                                                symbol = i
                                                break
                                        print(f"  [UPDATE] idx={idx} symbol={symbol} alis={alis} satis={satis} prev_alis={prev[1]} prev_satis={prev[2]} change_alis={change_alis} change_satis={change_satis} interval_ms={interval}")
                                    else:
                                        print(f"  [UPDATE] idx={idx} alis={alis} satis={satis} (first)")
                                    
                                    last_update_time[int(idx)] = (time.monotonic() * 1000, float(update[1]), float(update[2]))
                                    update_count += 1
                        
                        elif data.get("type") == "init":
                            print(f"  [WS] Re-init received (reconnect?)")
                        
                    except asyncio.TimeoutError:
                        continue
                        
            except asyncio.TimeoutError:
                pass
            except websockets.exceptions.ConnectionClosed as e:
                print(f"[WS] Connection closed: code={e.code}")
            except Exception as e:
                results["errors"].append(f"Listen error: {e}")
                print(f"[WS] Error: {e}")
        
        results["end_time"] = time.time()
        results["clean_shutdown"] = True
        print(f"\n[WS] Test completed for {endpoint_name}")
        
    except Exception as e:
        results["errors"].append(f"Connection error: {e}")
        print(f"[WS] Connection error: {e}")
    
    return results


async def main():
    import os
    import asyncio
    import json
    from datetime import datetime
    import statistics
    import websockets
    import aiohttp
    from dotenv import load_dotenv
    
    load_dotenv()
    
    print("="*80)
    print("AuTR WebSocket Endpoint Comparison: /ws/prices vs /ws/live")
    print("="*70)
    
    # TEST 1: /ws/prices (current production endpoint)
    print("\n>>> TEST 1: /ws/prices (current production endpoint)")
    print("Reference: connection OK, INIT OK, 112 symbols, 84 mapping, 0 live updates/60s")
    result1 = await test_endpoint(WS_PRICES_URL, "/ws/prices", duration=30)
    
    # Small delay between tests
    await asyncio.sleep(3)
    
    # TEST 2: /ws/live (documented live endpoint)
    print("\n>>> TEST 2: /ws/live (documented live endpoint)")
    result2 = await test_endpoint(WS_LIVE_URL, "/ws/live", duration=30)
    
    # COMPARISON REPORT
    print("\n" + "="*80)
    print("ENDPOINT COMPARISON REPORT")
    print("="*70)
    
    print("\nEndpoint | Connected | Init | Items | Live Updates | Update Count | Avg Interval | Status")
    print("-" * 85)
    
    for r in [result1, result2]:
        ep_name = r.get("endpoint_name", r.get("endpoint_name", "unknown"))
        conn = "YES" if r.get("connected") else "NO"
        init_ok = "YES" if r.get("init_received") else "NO"
        items = str(r.get("init_snapshot_count", 0))
        live_updates = str(r.get("update_count", 0))
        avg_int = "N/A"
        if r.get("update_intervals"):
            avg_int = f"{statistics.mean(r['update_intervals']):.0f}ms"
        status = "WORKING" if r.get("connected") and r.get("init_received") else "FAILED"
        if r.get("errors"):
            status = "ERROR"
        
        print(f"{r.get('endpoint_name', '?'):<12} | {conn:<9} | {init_ok:<4} | {items:<6} | {live_updates:<12} | {avg_int:<10} | {status}")
    
    print("\n" + "="*70)
    print("DETAILED FINDINGS")
    print("="*70)
    
    for r in [result1, result2]:
        print(f"\n--- {r.get('endpoint_name', 'unknown')} ---")
        print(f"  Endpoint: {r.get('ws_url', 'unknown')}")
        print(f"  Connected: {r.get('connected', False)}")
        print(f"  Init Received: {r.get('init_received', False)}")
        print(f"  Snapshot Items: {r.get('init_snapshot_count', 0)}")
        print(f"  Target Mappings Found: {len(r.get('target_mappings', {}))}")
        print(f"  Live Updates Received: {r.get('update_count', 0)}")
        if r.get("update_intervals"):
            intervals = r.get("update_intervals", [])
            if intervals:
                print(f"  Avg Update Interval: {statistics.mean(r['update_intervals']):.0f}ms")
                print(f"  Min/Max Interval: {min(r['update_intervals']):.0f}ms / {max(r['update_intervals']):.0f}ms")
        else:
            print("  Update Intervals: N/A (no updates received)")
        print(f"  Errors: {r.get('errors', [])}")
        print(f"  Clean Shutdown: {r.get('clean_shutdown', False)}")
        
        # GRAMALTIN search
        print("\n  GRAMALTIN search in INIT snapshot:")
        for item in init_data.get("snapshot", []) if 'init_data' in locals() else []:
            pass  # handled in test_endpoint
    
    # Save results
    results = {
        "timestamp": datetime.now().isoformat(),
        "test_summary": {
            "ws_prices": {
                "connected": result1.get("connected"),
                "init_received": result1.get("init_received"),
                "snapshot_count": result1.get("init_snapshot_count"),
                "target_mappings_found": len(result1.get("target_mappings", {})),
                "live_updates_count": result1.get("update_count", 0),
                "errors": result1.get("errors", []),
            },
            "ws_live": {
                "connected": result2.get("connected"),
                "init_received": result2.get("init_received"),
                "snapshot_count": result2.get("init_snapshot_count", 0),
                "target_mappings_found": len(result2.get("target_mappings", {})),
                "live_updates_count": result2.get("update_count", 0),
                "errors": result2.get("errors", []),
            }
        },
        "details": {
            "ws_prices": result1,
            "ws_live": result2,
        }
    }
    
    with open(RESULTS_FILE, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"\n[SAVED] Full results saved to: {RESULTS_FILE}")


if __name__ == "__main__":
    import os
    import asyncio
    import json
    from datetime import datetime
    import statistics
    import websockets
    import aiohttp
    from dotenv import load_dotenv
    
    load_dotenv()
    asyncio.run(main())