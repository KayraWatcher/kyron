#!/usr/bin/env python3
"""
AuTR Data Verification Script
Compares REST vs WS data, validates index mapping, investigates price discrepancies
"""

import asyncio
import json
import os
import time
from datetime import datetime
from typing import Dict, List

import websockets
import aiohttp
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")

TARGET_SYMBOLS = ["USDTRY", "EURTRY", "GRAMALTIN", "CEYREK_YENI", "GUMUSTRY"]
WS_URL = f"wss://autr.tr/ws/prices?api_key={API_KEY}"
REST_URL = "https://autr.tr/api/prices/live"
REST_HEADERS = {"X-API-Key": API_KEY}

RAW_REST_FILE = f"autr_raw_rest_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
RAW_WS_FILE = f"autr_raw_ws_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"


async def fetch_rest_snapshot() -> dict:
    """Fetch REST snapshot and save raw response"""
    print("\n=== FETCHING REST SNAPSHOT ===")
    async with aiohttp.ClientSession() as session:
        async with session.get(REST_URL, headers={"X-API-Key": API_KEY}) as resp:
            if resp.status != 200:
                text = await resp.text()
                print(f"[REST] Error {resp.status}: {await resp.text()}")
                return None
            data = await resp.json()
            
            with open(f"autr_raw_rest_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json", 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            print(f"[REST] Saved raw response")
            
            prices = data.get('data', data.get('prices', {}))
            print(f"[REST] Total symbols: {len(prices)}")
            
            rest_prices = {}
            for sym in TARGET_SYMBOLS:
                if sym in prices:
                    p = prices[sym]
                    rest_prices[sym] = {
                        'alis': p.get('alis'),
                        'satis': p.get('satis'),
                    }
                    print(f"  [REST] {sym}: alis={p.get('alis')}, satis={p.get('satis')}")
                else:
                    print(f"  [REST] {sym}: NOT FOUND")
            
            return {
                'prices': prices,
                'target': rest_prices,
                'symbol_order': list(prices.keys())
            }


async def fetch_ws_data():
    """Connect to WS and collect raw messages"""
    print("\n=== CONNECTING TO WEBSOCKET ===")
    
    uri = f"wss://autr.tr/ws/prices?api_key={API_KEY}"
    
    ws_messages = []
    init_snapshot = None
    updates = []
    
    async with websockets.connect(
        f"wss://autr.tr/ws/prices?api_key={API_KEY}",
        ping_interval=20,
        ping_timeout=10
    ) as ws:
        print("[WS] Connected")
        
        # First message should be init
        msg = await ws.recv()
        data = json.loads(msg)
        
        if data.get('type') == 'init':
            snapshot = data.get('snapshot', [])
            print(f"[WS] INIT snapshot received: {len(snapshot)} items")
            
            # Debug: print first 3 raw items
            for i, item in enumerate(snapshot[:3]):
                print(f"[DEBUG] snapshot[{i}]: {item}")
            
            # Save raw INIT message
            with open(f"autr_raw_init_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json", 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            
            return data
        
        return None


async def listen_for_updates(ws, duration=30):
    """Listen for WS updates"""
    updates = []
    start_time = time.monotonic()
    
    while time.monotonic() - start_time < duration:
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
            data = json.loads(msg)
            
            if data.get('type') == 'init':
                print(f"[WS] INIT received again (reconnect?)")
            elif isinstance(data, list) or (isinstance(data, dict) and data.get('type') != 'init'):
                print(f"[UPDATE] {data}")
            
        except asyncio.TimeoutError:
            continue
        except websockets.exceptions.ConnectionClosed:
            break
    
    return []


def compare_rest_vs_ws(rest_data: dict, ws_init: dict):
    """Compare REST and WS snapshot data"""
    print("\n=== REST vs WS COMPARISON ===")
    
    prices = rest_data['prices']
    target_rest = rest_data['target']
    
    print("\nREST Prices (target symbols):")
    for sym in TARGET_SYMBOLS:
        if sym in target_rest:
            p = target_rest[sym]
            print(f"  REST {sym}: alis={p.get('alis')}, satis={p.get('satis')}")
    
    # Analyze WS INIT snapshot
    snapshot = ws_init.get('snapshot', [])
    print(f"\nWS INIT Snapshot: {len(snapshot)} items")
    
    # Debug: print first 5 raw items
    print("\nWS INIT First 5 items:")
    for i, item in enumerate(snapshot[:5]):
        print(f"  snapshot[{i}]: {item}")
    
    # Check if snapshot items have symbol names or just indices
    print("\nSnapshot format analysis:")
    for i, item in enumerate(snapshot[:10]):
        if isinstance(item, list):
            print(f"  snapshot[{i}]: len={len(item)}, type=list, first_3={item[:3]}")
        elif isinstance(item, dict):
            print(f"  snapshot[{i}]: keys={list(item.keys())}")


async def main():
    import aiohttp
    import websockets
    
    print("="*60)
    print("AuTR DATA VERIFICATION SCRIPT")
    print("="*60)
    
    # 1. Fetch REST snapshot
    rest_data = await fetch_rest_snapshot()
    if not rest_data:
        print("[ERROR] REST fetch failed")
        return
    
    # 2. Connect WS and get INIT
    async with websockets.connect(
        f"wss://autr.tr/ws/prices?api_key={API_KEY}",
        ping_interval=20,
        ping_timeout=10
    ) as ws:
        msg = await ws.recv()
        init_data = json.loads(msg)
        
        if init_data.get('type') != 'init':
            print(f"[ERROR] Expected INIT, got: {msg[:200]}")
            return
        
        # 3. Compare
        compare_rest_vs_ws(rest_data, init_data)
        
        # 4. Listen for live updates (10 seconds)
        print("\n[WS] Listening for live updates (10s)...")
        start_time = time.monotonic()
        update_count = 0
        
        while time.monotonic() - time.monotonic() < 10:
            try:
                msg = await asyncio.wait_for(ws.recv(), timeout=2.0)
                data = json.loads(msg)
                
                if data.get('type') == 'init':
                    print("[WS] INIT received again")
                elif isinstance(data, list):
                    print(f"[UPDATE] {data}")
                else:
                    print(f"[OTHER] {data}")
                    
            except asyncio.TimeoutError:
                continue
            except websockets.exceptions.ConnectionClosed:
                break
        
        elapsed = time.monotonic() - time.monotonic()
        print(f"\n[WS] Test completed in {elapsed:.1f}s")


if __name__ == "__main__":
    asyncio.run(main())