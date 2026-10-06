#!/usr/bin/env python3
"""
AuTR WebSocket Endpoint Comparison Test
Tests /ws/prices vs /ws/live endpoints
"""

import asyncio
import json
import os
import time
from datetime import datetime
from typing import Dict, List, Tuple, Set, Optional

import websockets
import aiohttp
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")

TARGET_INDICES = {93, 90, 17, 8}

WS_PRICES_URL = f"wss://autr.tr/ws/prices?api_key={API_KEY}"
WS_LIVE_URL = f"wss://autr.tr/ws/live?api_key={os.getenv('AUTR_API_KEY')}"

RESULTS_FILE = f"autr_endpoint_comparison_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"


async def test_endpoint(ws_url: str, test_name: str, duration: int = 15) -> dict:
    """Test a WebSocket endpoint and return results"""
    
    print(f"\n{'='*60}")
    print(f"TESTING: {test_name}")
    print(f"URL: {ws_url}")
    print(f"Duration: {duration}s")
    print("="*60)
    
    results = {
        "endpoint": ws_url,
        "test_name": test_name,
        "connected": False,
        "init_received": False,
        "init_snapshot_count": 0,
        "target_mappings": {},
        "updates": [],
        "update_intervals": [],
        "errors": [],
        "clean_shutdown": False,
        "start_time": None,
        "end_time": None,
    }
    
    try:
        print(f"[WS] Connecting to {ws_url}...")
        async with websockets.connect(
            ws_url,
            ping_interval=20,
            ping_timeout=10,
            close_timeout=5
        ) as ws:
            print(f"[WS] Connected to {ws_url}")
            results["connected"] = True
            
            # Receive INIT
            msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
            data = json.loads(msg)
            
            if data.get('type') != 'init':
                results["errors"].append(f"Expected INIT, got: {msg[:200]}")
                return results
            
            print(f"[WS] INIT received")
            results["init_received"] = True
            results["init_snapshot_count"] = len(data.get('snapshot', []))
            
            # Check target indices in snapshot
            for item in data.get('snapshot', []):
                if isinstance(item, list) and len(item) >= 3:
                    parite_idx = int(item[0])
                    if parite_idx in [93, 90, 17, 8]:
                        results["target_mappings"][parite_idx] = {
                            "alis": float(item[1]),
                            "satis": float(item[2]),
                            "raw": item
                        }
            
            # Print target mappings
            print(f"\n[INIT] Snapshot items: {len(data.get('snapshot', []))}")
            for idx in [93, 90, 17, 8]:
                if idx in results["target_mappings"]:
                    m = results["target_mappings"][idx]
                    print(f"  idx {idx}: alis={m['alis']}, satis={m['satis']}")
                else:
                    print(f"  idx {idx}: NOT FOUND in snapshot")
            
            # Listen for updates
            print(f"\n[WS] Listening for updates ({duration}s)...")
            start_time = time.monotonic()
            last_update_time = {}
            update_count = 0
            
            try:
                while time.monotonic() - start_time < duration:
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=2.0)
                        data = json.loads(msg)
                        
                        if data.get('type') == 'init':
                            print(f"  [WS] Re-init received (reconnect?)")
                            continue
                        
                        if isinstance(data, list):
                            for update in data:
                                if not isinstance(update, list) or len(update) < 3:
                                    continue
                                idx, alis, satis = update[0], update[1], update[2]
                                if int(idx) in [93, 90, 17, 8]:
                                    prev = last_update_time.get(idx, (None, None))
                                    now = time.monotonic() * 1000
                                    if prev[0] is not None:
                                        interval = now - prev[0]
                                        print(f"  [UPDATE] idx={idx} alis={alis} satis={satis} interval={interval:.0f}ms")
                                    else:
                                        print(f"  [UPDATE] idx={idx} alis={alis} satis={satis} (first)")
                                    
                                    last_update_time[idx] = (time.monotonic() * 1000, alis, satis)
                        
                        elif data.get('type') == 'init':
                            print(f"  [WS] Re-init received")
                        
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
        print(f"\n[WS] Test completed for {test_name}")
        
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
    
    print("="*70)
    print("AuTR WebSocket Endpoint Comparison: /ws/prices vs /ws/live")
    print("="*70)
    
    # Test 1: /ws/prices (current endpoint)
    print("\n>>> TEST 1: /ws/prices (current production endpoint)")
    result1 = await test_endpoint(WS_PRICES_URL, "/ws/prices", duration=15)
    
    # Small delay between tests
    await asyncio.sleep(2)
    
    # Test 2: /ws/live (documented endpoint)
    print("\n>>> TEST 2: /ws/live (documented live endpoint)")
    result2 = await test_endpoint(WS_LIVE_URL, "/ws/live", duration=15)
    
    # Comparison report
    print("\n" + "="*70)
    print("COMPARISON REPORT")
    print("="*70)
    
    for r in [result1, result2]:
        print(f"\n--- {r['test_name']} ---")
        print(f"  Endpoint: {r['endpoint']}")
        print(f"  Connected: {r['connected']}")
        print(f"  Init Received: {r['init_received']}")
        print(f"  Init Snapshot Items: {r['init_snapshot_count']}")
        print(f"  Target Mappings Found: {len(r['target_mappings'])}")
        print(f"  Errors: {len(r['errors'])}")
        print(f"  Clean Shutdown: {r['clean_shutdown']}")
        for idx in [93, 90, 17, 8]:
            if idx in r.get('target_mappings', {}):
                m = r['target_mappings'][idx]
                print(f"  idx {idx}: alis={m['alis']}, satis={m['satis']}")
            else:
                print(f"  idx {idx}: NOT FOUND")
    
    # Comparison table
    print("\n" + "="*80)
    print("COMPARISON TABLE")
    print("="*80)
    print(f"{'Endpoint':<15} | {'Connected':<10} | {'Init':<5} | {'Items':<6} | {'Updates':<8} | {'Status':<12}")
    print("-"*80)
    
    for r in [result1, result2]:
        ep = r['endpoint'].split('/')[-1]
        conn = "YES" if r['connected'] else "NO"
        init = "YES" if r['init_received'] else "NO"
        items = str(r['init_snapshot_count'])
        status = "LIVE" if r['connected'] and r['init_received'] else "FAILED"
        if r.get('errors'):
            status = "ERROR"
        
        print(f"{r['test_name']:<15} | {'YES' if r['connected'] else 'NO':<10} | {'YES' if r['init_received'] else 'NO':<5} | {r['init_snapshot_count']:<6} | {'N/A':<8} | {r.get('test_name', 'N/A'):<12}")
    
    # Live update capability
    print("\n" + "="*70)
    print("LIVE UPDATE CAPABILITY")
    print("="*70)
    for r in [result1, result2]:
        ep = r['endpoint'].split('/')[-1]
        # We didn't capture updates in this version
        print(f"  {r['test_name']}: Test completed - check INIT snapshot only")
    
    # Save results
    results = {
        "timestamp": datetime.now().isoformat(),
        "ws_prices": result1,
        "ws_live": result2,
    }
    
    with open(RESULTS_FILE, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"\n[SAVED] Full results saved to: {RESULTS_FILE}")


if __name__ == "__main__":
    import os
    import asyncio
    import json
    from datetime import datetime
    import websockets
    import aiohttp
    from dotenv import load_dotenv
    
    load_dotenv()
    asyncio.run(main())