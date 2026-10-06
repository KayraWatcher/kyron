#!/usr/bin/env python3
"""
AuTR WebSocket PoC - Standalone test script
Tests real-time FX + Altın + Gümüş + Çeyrek streaming from autr.tr

Official Docs: https://autr.tr/sayfa/atr-doviz-kuru-api-dokumantasyonu
WS Doc: https://autr.tr/api-servisi/websocket-canli-kur-servisi

WS Endpoint: wss://autr.tr/ws/prices?api_key=ak_live_YOUR_KEY
REST: https://autr.tr/api/prices/live (X-API-Key header)

Auth: ak_live_... key as query param or X-API-Key header
WS Init: {"type": "init", "snapshot": [[idx, alis, satis], ...]}
WS Updates: [[parite_idx, alis_fiyati, satis_fiyati], ...]

Requirements:
- Python 3.8+
- pip install websockets aiohttp python-dotenv

Usage:
1. Register at https://autr.tr/register
2. Get API Key from https://autr.tr/user/api-key (format: ak_live_...)
3. Copy .env.example to .env and fill in your API key
4. python autr_poc.py
"""

import asyncio
import json
import os
import time
from datetime import datetime
from typing import Optional, Dict, List
import statistics

import websockets
import aiohttp
from dotenv import load_dotenv

load_dotenv()


class AuTRPoC:
    def __init__(self):
        self.api_key = os.getenv("AUTR_API_KEY")
        if not self.api_key:
            raise ValueError("AUTR_API_KEY not set in .env")
        
        # REST & WS endpoints (official docs)
        self.rest_url = "https://autr.tr/api/prices/live"
        self.ws_url = f"wss://autr.tr/ws/prices?api_key={self.api_key}"
        
        # Target symbols (official AuTR symbol names from docs)
        self.target_symbols = {
            "USDTRY": "USDTRY",
            "EURTRY": "EURTRY", 
            "GRAMALTIN": "GRAMALTIN",
            "CEYREK_YENI": "CEYREK_YENI",
            "GUMUSTRY": "GUMUSTRY",
        }
        
        # AuTR WS sends index-based updates, we need symbol mapping
        self.idx_to_symbol: Dict[int, str] = {}
        self.symbol_to_idx: Dict[str, int] = {}
        self.rest_symbol_order: List[str] = []
        self.rest_prices: Dict = {}
        
        if not self.api_key:
            raise ValueError("AUTR_API_KEY not set in .env")
        
        # Validate key format
        if not self.api_key.startswith("ak_live_"):
            print("WARNING: API key should start with 'ak_live_' prefix per docs")
            print(f"   Current key prefix: {self.api_key[:10]}...")
        
        # Statistics tracking
        self.events: list = []
        self.last_prices: dict = {}
        self.update_intervals: dict = {}
        self.last_event_time: dict = {}
        self.duplicate_count = 0
        self.error_count = 0
        self.reconnect_count = 0
        self.start_time = time.monotonic()
        self.ws = None
        self.running = False
        self.snapshot_received = False
        
    async def test_rest_snapshot(self) -> dict:
        """Test REST API snapshot before WebSocket"""
        print(f"\n[REST] Requesting snapshot from https://autr.tr/api/prices/live")
        start = time.monotonic()
        
        async with aiohttp.ClientSession() as session:
            print("[REST] ClientSession created")
            async with session.get("https://autr.tr/api/prices/live", headers={"X-API-Key": self.api_key}) as resp:
                latency = (time.monotonic() - start) * 1000
                if resp.status != 200:
                    text = await resp.text()
                    print(f"[REST] Error {resp.status}: {await resp.text()}")
                    if resp.status == 401:
                        print("   [ERROR] 401: Invalid API key (should be ak_live_... format)")
                    elif resp.status == 403:
                        print("   [ERROR] 403: Plan/IP restriction")
                    return {}
                
                data = await resp.json()
                print(f"[REST] Response in {(time.monotonic() - start) * 1000:.1f}ms, status={resp.status}")
                print(f"[REST] Status: {data.get('status')}")
                print(f"[REST] Timestamp: {data.get('timestamp')}")
                print(f"[REST] Latency: {data.get('latency_ms')}ms")
                
                prices = data.get('data', data.get('prices', {}))
                print(f"[REST] Symbols returned: {len(prices)}")
                
                # Build symbol order from REST response (order should match WS snapshot index)
                self.rest_symbol_order = list(prices.keys())
                self.rest_prices = prices
                print(f"[REST] Symbol order (first 10): {self.rest_symbol_order[:10]}")
                
                # Show our target symbols
                for sym in self.target_symbols:
                    if sym in prices:
                        p = prices[sym]
                        print(f"  [OK] {sym}: alis={p.get('alis')}, satis={p.get('satis')}")
                return data

    def _build_idx_mapping(self, snapshot: list):
        """Build index -> symbol mapping from WS snapshot using REST symbol order"""
        # WS snapshot format: [[parite_idx, alis, satis], ...]
        # The array index in snapshot corresponds to the order in REST response
        self.idx_to_symbol.clear()
        self.symbol_to_idx.clear()
        
        for idx, item in enumerate(snapshot):
            if not isinstance(item, list) or len(item) < 3:
                continue
            # Snapshot format: [parite_idx, alis, satis]
            # The array position (idx) corresponds to REST symbol order
            if idx < len(self.rest_symbol_order):
                sym = self.rest_symbol_order[idx]
                self.idx_to_symbol[idx] = sym
                self.symbol_to_idx[sym] = idx
                if sym in self.target_symbols:
                    print(f"[MAP] idx {idx} -> {sym}")
            else:
                # Fallback
                self.idx_to_symbol[idx] = f"IDX_{idx}"

    def _process_ws_message(self, msg: dict, receive_time_ms: float):
        """Process incoming WebSocket message"""
        msg_type = msg.get('type')
        
        if msg_type == 'init':
            # Initial snapshot: {"type": "init", "snapshot": [[idx, alis, satis], ...]}
            snapshot = msg.get('snapshot', [])
            print(f"\n[WS] [INIT] SNAPSHOT received: {len(snapshot)} symbols")
            
            # Debug: print first 2-3 raw snapshot items (safe, no API key)
            for i, item in enumerate(snapshot[:3]):
                print(f"[DEBUG] snapshot[{i}]: {item}")
            
            self._build_idx_mapping(msg.get('snapshot', []))
            self.snapshot_received = True
            
            # Process snapshot items for initial prices
            for idx, item in enumerate(snapshot):
                if not isinstance(item, list) or len(item) < 3:
                    continue
                # Snapshot format: [parite_idx, alis, satis]
                if idx < len(self.rest_symbol_order):
                    sym = self.rest_symbol_order[idx]
                    if sym in self.target_symbols:
                        alis = item[1] if len(item) > 1 else None
                        satis = item[2] if len(item) > 2 else None
                        self._process_update(sym, {'alis': item[1], 'satis': item[2]}, time.monotonic() * 1000)
            return
        
        # Update format: [[parite_idx, alis_fiyati, satis_fiyati], ...]
        if isinstance(msg, list):
            for update in msg:
                if not isinstance(update, list) or len(update) < 3:
                    continue
                idx, alis, satis = update[0], update[1], update[2]
                sym = self.idx_to_symbol.get(idx)
                if sym in self.target_symbols:
                    self._process_update(sym, {'alis': alis, 'satis': satis}, time.monotonic() * 1000)

    def _process_update(self, symbol: str, data: dict, receive_time_ms: float):
        """Process price update for a symbol"""
        alis = data.get('alis')
        satis = data.get('satis')
        
        if alis is None or satis is None:
            return
        
        # Provider timestamp not in update messages, use receive time
        provider_ts = int(time.time() * 1000)
        receive_time = time.monotonic() * 1000
        latency_ms = 0  # No provider timestamp in updates
        
        event = {
            "symbol": symbol,
            "bid": float(alis) if alis is not None else None,
            "ask": float(satis) if satis is not None else None,
            "provider_timestamp": int(time.time() * 1000),
            "local_receive_timestamp": datetime.now().isoformat(),
            "latency_ms": 0,
        }
        
        self._track_event(event)

    def _track_event(self, event: dict):
        """Track event for statistics"""
        self.events.append(event)
        sym = event['symbol']
        
        # Track update intervals
        now_ms = time.monotonic() * 1000
        if sym in self.last_event_time:
            interval = now_ms - self.last_event_time[sym]
            if sym not in self.update_intervals:
                self.update_intervals[sym] = []
            self.update_intervals[sym].append(interval)
        self.last_event_time[sym] = now_ms
        
        # Check for duplicate (same bid/ask)
        key = (event['symbol'], event['bid'], event['ask'])
        last_key = self.last_prices.get(sym)
        if last_key == key:
            self.duplicate_count += 1
            print(f"  [DUPLICATE] {sym} same values")
        self.last_prices[sym] = key
        
        # Print event
        changed = ""
        if self.last_prices.get(sym) != (event['symbol'], event['bid'], event['ask']):
            changed = " [CHANGED]"
        print(f"  [EVENT] {event['symbol']}: alis={event['bid']}, satis={event['ask']}{changed}")

    async def run_poc(self):
        """Main PoC execution"""
        print("="*60)
        print("AuTR WebSocket PoC - Official Docs Compliant")
        print("="*60)
        print(f"REST: https://autr.tr/api/prices/live (X-API-Key header)")
        print(f"WS: wss://autr.tr/ws/prices?api_key=ak_live_...")
        print(f"Target Symbols: {list(self.target_symbols.keys())}")
        print("")
        
        # 1. Test REST snapshot
        await self.test_rest_snapshot()
        
        # 2. Connect WebSocket
        print(f"\n[WS] Connecting to wss://autr.tr/ws/prices?api_key=ak_live_...")
        try:
            print(f"[WS] Attempting connection...")
            self.ws = await websockets.connect(
                f"wss://autr.tr/ws/prices?api_key={self.api_key}",
                ping_interval=20,
                ping_timeout=10,
                close_timeout=10,
            )
            print(f"[WS] Connected successfully")
        except Exception as e:
            print(f"[WS] Connection failed: {e}")
            if "401" in str(e) or "403" in str(e) or "Unauthorized" in str(e) or "Forbidden" in str(e):
                print("   [ERROR] Auth failed - Check:")
                print("      1. API key format: ak_live_... (per docs)")
                print("      2. Free plan may have WS restrictions")
                print("      3. IP whitelist in dashboard")
            return
        
        # Listen for messages (60 seconds for full test)
        TEST_DURATION = 60  # seconds
        print(f"\n[WS] Listening for updates for {TEST_DURATION} seconds...")
        print("-" * 60)
        print("[WS] Waiting for messages...")
        
        self.running = True
        self.start_time = time.monotonic()
        
        # Use asyncio.wait_for to limit the test duration
        async def listen_loop():
            async for message in self.ws:
                if not self.running:
                    break
                
                try:
                    msg = json.loads(message)
                    self._process_ws_message(msg, time.monotonic() * 1000)
                except json.JSONDecodeError as e:
                    print(f"  [WARN] JSON decode error: {e}")
                    self.error_count += 1
                except Exception as e:
                    print(f"  [WARN] Message processing error: {e}")
                    self.error_count += 1
        
        try:
            await asyncio.wait_for(listen_loop(), timeout=TEST_DURATION)
        except asyncio.TimeoutError:
            print(f"\n[WS] Test duration ({TEST_DURATION}s) completed")
        except websockets.exceptions.ConnectionClosed as e:
            print(f"\n[WS] Connection closed: code={e.code}, reason={e.reason}")
            self.error_count += 1
        except Exception as e:
            print(f"\n[WS] Listen error: {e}")
            self.error_count += 1
        finally:
            self.running = False
            self._print_statistics()

    def _print_statistics(self):
        """Print collected statistics"""
        print("\n" + "="*60)
        print("AuTR WebSocket PoC STATISTICS")
        print("="*60)
        print(f"Total events received: {len(self.events)}")
        print(f"Duplicate events: {self.duplicate_count}")
        print(f"Runtime: {(time.monotonic() - self.start_time):.1f}s")
        
        print("\n--- Update Intervals (ms) ---")
        for symbol, intervals in self.update_intervals.items():
            if not intervals:
                continue
            intervals_sorted = sorted(intervals)
            min_i = min(intervals)
            max_i = max(intervals)
            median_i = statistics.median(intervals)
            p95_i = intervals_sorted[int(len(intervals_sorted) * 0.95)]
            avg_i = statistics.mean(intervals)
            print(f"  {symbol}: count={len(intervals)}, min={min_i:.1f}, median={median_i:.1f}, "
                  f"p95={p95_i:.1f}, max={max_i:.1f}, avg={statistics.mean(intervals):.1f}")
        
        print(f"\nDuplicate events: {self.duplicate_count}/{len(self.events)} ({100*self.duplicate_count/len(self.events) if self.events else 0:.1f}%)")
        
        print("\n--- Last Known Prices ---")
        for symbol, data in self.last_prices.items():
            print(f"  {symbol}: alis={data[0]}, satis={data[1]}")
        
        # Verdict
        self._print_verdict()

    def _print_verdict(self):
        """Print final verdict"""
        print("\n" + "="*60)
        print("VERDICT: AuTR WebSocket vs Yahoo 3s Polling")
        print("="*60)
        
        if len(self.events) == 0:
            print("[FAIL] NO EVENTS RECEIVED")
            return
        
        usdtry_intervals = self.update_intervals.get("USDTRY", [])
        if not usdtry_intervals:
            print("[WARN] No USDTRY intervals recorded")
            return
        
        avg_interval = statistics.mean(self.update_intervals.get("USDTRY", [3000]))
        median_interval = statistics.median(self.update_intervals.get("USDTRY", [3000]))
        
        print(f"\n--- Comparison with Yahoo 3s Polling ---")
        print(f"Yahoo: Fixed 3000ms interval, HTTP overhead, ~500ms latency")
        print(f"AuTR: avg interval={statistics.mean(self.update_intervals.get('USDTRY', [3000])):.0f}ms, median={statistics.median(self.update_intervals.get('USDTRY', [3000])):.0f}ms")
        if self.events:
            print(f"Total events: {len(self.events)}")
        
        if len(self.events) > 10 and statistics.median(self.update_intervals.get("USDTRY", [3000])) < 1000:
            print("\n[PASS] VERDICT: AuTR WebSocket PROVIDES REAL-TIME updates")
        elif len(self.events) > 0:
            print("\n[PARTIAL] VERDICT: AuTR WebSocket WORKS but check update frequency")
        else:
            print("\n[FAIL] VERDICT: AuTR WebSocket NOT WORKING for real-time")


def main():
    print("[DEBUG] main() started")
    import os
    if not os.getenv("AUTR_API_KEY"):
        print("[FAIL] AUTR_API_KEY not set in .env")
        print("Create .env with: AUTR_API_KEY=ak_live_...")
        return
    
    print("[DEBUG] API key found, creating PoC instance")
    poc = AuTRPoC()
    print("[DEBUG] PoC instance created, starting run_poc")
    asyncio.run(poc.run_poc())


if __name__ == "__main__":
    main()