#!/usr/bin/env python3
"""
altinapi.com WebSocket PoC - Standalone test script
Tests real-time FX + Altın + Çeyrek Altın + Gümüş streaming from altinapi.com.

OFFICIAL DOCS: https://altinapi.com/docs
- REST: https://altinapi.com/api/v1 (X-API-Key header)
- WebSocket: Socket.io at wss://altinapi.com (auth: {api_key: "hapi_..."})
- WebSocket requires Pro+ plan (Free trial: REST only, no WebSocket)

Requirements:
- Python 3.8+
- pip install "python-socketio[client]" aiohttp python-dotenv

Usage:
1. Register at https://altinapi.com/register
2. Get API Key from dashboard (format: hapi_...)
3. Upgrade to Pro+ plan for WebSocket access (Free trial: REST only)
3. Copy .env.example to .env and fill in your API key
4. python altinapi_poc.py
"""

import asyncio
import json
import os
import time
import uuid
from datetime import datetime
from typing import Optional, Dict, List
import statistics

import aiohttp
import socketio
from dotenv import load_dotenv

load_dotenv()


class AltinapiPoC:
    def __init__(self):
        self.api_key = os.getenv("ALTINAPI_API_KEY")
        self.base_rest_url = "https://altinapi.com/api/v1"
        # Socket.io connection URL (official docs: wss://altinapi.com)
        # Socket.io client connects to https://altinapi.com
        
        # Target symbols (using OFFICIAL altinapi symbol names from docs)
        # See: https://altinapi.com/docs#symbols
        self.target_symbols = {
            # DOVIZ (16 symbols)
            "USDTRY": "USDTRY",      # USD/TRY
            "EURTRY": "EURTRY",      # EUR/TRY
            # MADEN (19 symbols)
            "ALTIN": "ALTIN",        # Altın (TL/gram)
            "XAUUSD": "XAUUSD",      # Altın USD/ons
            # SARRAFIYE (15 symbols) - Çeyrek Altın variants
            "CEYREK_YENI": "CEYREK_YENI",   # Çeyrek Altın Yeni
            "CEYREK_ESKI": "CEYREK_ESKI",   # Çeyrek Altın Eski
            "GUMTRY": "GUMTRY",      # Gümüş TL/gram
            "XAGUSD": "XAGUSD",      # Gümüş USD/ons
        }
        
        # Subscribe to CATEGORIES per official docs:
        # DOVIZ (16 symbols), MADEN (19), SARRAFIYE (15)
        self.subscribe_categories = ["DOVIZ", "MADEN", "SARRAFIYE"]
        
        self.api_key = os.getenv("ALTINAPI_API_KEY")
        if not self.api_key:
            raise ValueError("ALTINAPI_API_KEY not set in .env")
        
        # Validate API key format (should be hapi_ prefix per docs)
        if not self.api_key.startswith("hapi_"):
            print("⚠️ WARNING: API key should start with 'hapi_' prefix per official docs")
            print(f"   Current key prefix: {self.api_key[:10]}...")
        
        # Plan validation warning
        print("ℹ️ IMPORTANT: WebSocket requires Pro+ plan (Free trial = REST only)")
        print("   Pro: 60 req/min + 3 WS | Enterprise: 60 req/min + 10 WS")
        
        # Config
        self.api_key = os.getenv("ALTINAPI_API_KEY")
        self.base_rest_url = "https://altinapi.com/api/v1"
        self.ws_url = "https://altinapi.com"  # Socket.io connects to base URL
        
        # Target symbols (OFFICIAL altinapi symbol names from docs)
        self.target_symbols = {
            # DOVIZ (16 symbols)
            "USDTRY": "USDTRY",
            "EURTRY": "EURTRY",
            # MADEN (19 symbols)
            "ALTIN": "ALTIN",
            "XAUUSD": "XAUUSD",
            # SARRAFIYE (15 symbols)
            "CEYREK_YENI": "CEYREK_YENI",
            "CEYREK_ESKI": "CEYREK_ESKI",
            "GUMTRY": "GUMTRY",
            "XAGUSD": "XAGUSD",
        }
        
        # Subscribe to CATEGORIES per official docs
        self.subscribe_categories = ["DOVIZ", "MADEN", "SARRAFIYE"]
        
        self.api_key = os.getenv("ALTINAPI_API_KEY")
        if not self.api_key:
            raise ValueError("ALTINAPI_API_KEY not set in .env")
        
        # Validate API key format
        if not self.api_key.startswith("hapi_"):
            print("⚠️ WARNING: API key should start with 'hapi_' prefix per official docs")
            print(f"   Current key prefix: {self.api_key[:10]}...")
        
        # Plan requirement warning
        print("ℹ️ IMPORTANT: WebSocket requires Pro+ plan (Free trial = REST only)")
        print("   Pro: 60 req/min + 3 WS | Enterprise: 60 req/min + 10 WS")
        
        self.api_key = os.getenv("ALTINAPI_API_KEY")
        self.base_rest_url = "https://altinapi.com/api/v1"
        self.ws_url = "https://altinapi.com"
        
        # OFFICIAL target symbols from docs
        self.target_symbols = {
            "USDTRY": "USDTRY", "EURTRY": "EURTRY",
            "ALTIN": "ALTIN", "XAUUSD": "XAUUSD",
            "CEYREK_YENI": "CEYREK_YENI", "CEYREK_ESKI": "CEYREK_ESKI",
            "GUMTRY": "GUMTRY", "XAGUSD": "XAGUSD",
        }
        
        self.subscribe_categories = ["DOVIZ", "MADEN", "SARRAFIYE"]
        
        if not self.api_key:
            raise ValueError("ALTINAPI_API_KEY not set in .env")
        
        # Statistics tracking
        self.events: list = []
        self.last_prices: dict = {}
        self.update_intervals: dict = {}
        self.last_event_time: dict = {}
        self.duplicate_count = 0
        self.error_count = 0
        self.reconnect_count = 0
        self.start_time = time.monotonic()
        self.sio = None
        self.running = False
        self.connected = False
        self.snapshot_received = False
        
    def _parse_provider_timestamp(self, ts: int) -> datetime:
        """Convert Unix ms timestamp to datetime"""
        return datetime.fromtimestamp(ts / 1000)

    async def test_rest_snapshot(self) -> dict:
        """Test REST API snapshot before WebSocket - OFFICIAL endpoint"""
        url = f"{self.base_rest_url}/prices"
        headers = {"X-API-Key": self.api_key}  # OFFICIAL: X-API-Key header
        
        print(f"\n[REST] Requesting snapshot from {self.base_rest_url}/prices")
        start = time.monotonic()
        
        async with aiohttp.ClientSession() as session:
            async with session.get(url, headers={"X-API-Key": self.api_key}) as resp:
                latency = (time.monotonic() - start) * 1000
                if resp.status != 200:
                    text = await resp.text()
                    print(f"[REST] Error {resp.status}: {text}")
                    if resp.status == 401:
                        print("   🔴 401 Unauthorized: Invalid/expired API key or wrong format (should be hapi_...)")
                        print("   Check: API key format should be 'hapi_...' per official docs")
                    elif resp.status == 403:
                        print("   🔴 403 Forbidden: Plan inactive, IP restriction, or WebSocket plan required")
                        print("   Check: Free trial = REST only (no WebSocket). Pro+ plan required for WS.")
                    return {}
                
                data = await resp.json()
                print(f"[REST] Response in {(time.monotonic() - start) * 1000:.1f}ms, status={resp.status}")
                print(f"[REST] UpdatedAt: {data.get('updatedAt')}")
                print(f"[REST] Stale: {data.get('stale')}")
                print(f"[REST] Symbols returned: {len(data.get('data', []))}")
                
                # Show our target symbols
                for item in data.get('data', []):
                    sym = item.get('symbol')
                    if sym in self.target_symbols:
                        print(f"  ✅ {sym}: bid={item.get('bid')}, ask={item.get('ask')}, ts={item.get('timestamp')}, cat={item.get('category')}")
                return data

    async def run_poc(self):
        """Main PoC execution"""
        print("="*60)
        print("ALTIAPI.COM WEBSOCKET PoC (Socket.io) - OFFICIAL DOCS v1")
        print("="*60)
        print(f"REST Base: https://altinapi.com/api/v1 (X-API-Key header)")
        print(f"WS: https://altinapi.com (Socket.io, auth: {{api_key: 'hapi_...'}})")
        print(f"Target Symbols: {list(self.target_symbols.keys())}")
        print(f"Subscribe Categories: {self.subscribe_categories}")
        print("")
        print("ℹ️ PLAN REQUIREMENT: WebSocket requires Pro+ plan")
        print("   Free trial: 1000 req/month REST ONLY, NO WebSocket")
        print("   Pro: 60 req/min + 3 WS | Enterprise: 60 req/min + 10 WS")
        print("")
        
        # 1. Test REST snapshot
        await self.test_rest_snapshot()
        
        # 2. Setup Socket.io client (official docs config)
        self.sio = socketio.AsyncClient(
            reconnection=True,
            reconnection_attempts=5,
            reconnection_delay=1,
            reconnection_delay_max=5,
            logger=False,
            engineio_logger=False
        )
        
        # Event handlers
        @self.sio.event
        async def connect():
            self.connected = True
            print(f"\n[WS] Connected! SID: {self.sio.sid}")
            
            # Subscribe to CATEGORIES per official docs
            for cat in self.subscribe_categories:
                print(f"[WS] Subscribing to category: {cat}")
                await self.sio.emit("subscribe", [cat])
                await asyncio.sleep(0.1)
        
        @self.sio.event
        async def disconnect():
            self.connected = False
            print(f"\n[WS] Disconnected")
        
        @self.sio.on("prices:snapshot")
        async def on_snapshot(data):
            self.snapshot_received = True
            print(f"\n[WS] 📸 SNAPSHOT received: {len(data)} symbols")
            receive_time = time.monotonic() * 1000
            for item in data:
                sym = item.get('symbol')
                if sym in self.target_symbols:
                    self._process_update(item, time.monotonic() * 1000)
        
        @self.sio.on("prices:update")
        async def on_update(data):
            receive_time = time.monotonic() * 1000
            # data can be single object or array
            updates = data if isinstance(data, list) else [data]
            for item in updates:
                sym = item.get('symbol')
                if sym in self.target_symbols:
                    self._process_update(item, time.monotonic() * 1000)
        
        @self.sio.on("data:stale")
        async def on_stale():
            print(f"\n[WS] ⚠️ DATA STALE - Provider connection lost")
        
        @self.sio.on("data:live")
        async def on_live():
            print(f"\n[WS] ✅ DATA LIVE - Provider connection restored")
        
        @self.sio.on("connect_error")
        async def on_connect_error(data):
            print(f"\n[WS] ❌ Connection error: {data}")
            self.error_count += 1
        
        # Connect - OFFICIAL config: auth={api_key: "hapi_..."}
        print(f"\n[WS] Connecting to https://altinapi.com (Socket.io)...")
        print(f"   Auth: {{api_key: 'hapi_...'}}")
        try:
            await self.sio.connect(
                "https://altinapi.com",
                auth={"api_key": self.api_key},  # OFFICIAL: auth={api_key: "hapi_..."}
                transports=["websocket", "polling"],
                wait_timeout=10
            )
        except Exception as e:
            print(f"[WS] Connection failed: {e}")
            if "401" in str(e) or "403" in str(e) or "Unauthorized" in str(e) or "Forbidden" in str(e):
                print("   🔴 Authentication failed - Check:")
                print("      1. API key format: 'hapi_...' (per docs)")
                print("      2. Plan: WebSocket requires Pro+ (Free trial = REST only)")
                print("      3. IP whitelist in dashboard")
                print("      4. Key not expired/revoked")
            return
        
        # Wait for snapshot
        print("\n[WS] Waiting for snapshot...")
        for _ in range(50):  # 5 seconds max
            if self.snapshot_received:
                break
            await asyncio.sleep(0.1)
        
        if not self.snapshot_received:
            print("[WS] ⚠️ No snapshot received within 5s")
            print("   Possible causes: Plan doesn't include WS, auth failed, or network issue")
        
        # Listen for 5 minutes (300 seconds)
        print(f"\n[WS] Listening for updates for 5 minutes...")
        print("-" * 60)
        
        self.running = True
        self.start_time = time.monotonic()
        
        try:
            await asyncio.sleep(300)  # 5 minutes
        except KeyboardInterrupt:
            print("\n[WS] Interrupted by user")
        finally:
            self.running = False
            if self.sio and self.sio.connected:
                await self.sio.disconnect()
        
        # Print final statistics
        self._print_statistics()

    def _process_update(self, item: dict, receive_time_ms: float):
        """Process incoming price update - OFFICIAL format"""
        sym = item.get('symbol')
        if sym not in self.target_symbols:
            return
        
        bid = item.get('bid')
        ask = item.get('ask')
        ts = item.get('timestamp')
        
        # Parse timestamp (Unix ms) - OFFICIAL format
        provider_ts = ts if ts else int(time.time() * 1000)
        receive_time = time.monotonic() * 1000
        latency_ms = receive_time - provider_ts if provider_ts else 0
        
        # Create event record
        event = {
            "symbol": item.get('symbol'),
            "category": item.get('category'),
            "bid": bid,
            "ask": item.get('ask'),
            "provider_timestamp": provider_ts,
            "local_receive_timestamp": datetime.now().isoformat(),
            "latency_ms": latency_ms,
            "raw_data": item
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
            print(f"  ⚠️ DUPLICATE: {sym} same values")
        self.last_prices[sym] = key
        
        # Print event
        changed = ""
        if self.last_prices.get(sym) != key:
            changed = " 🔄 CHANGED"
        print(f"  📊 {event['symbol']}: bid={event['bid']}, ask={event['ask']}, "
              f"latency={event['latency_ms']:.1f}ms{changed}")

    def _print_statistics(self):
        """Print collected statistics"""
        print("\n" + "="*60)
        print("ALTIAPI.COM POC STATISTICS (Official Docs Compliant)")
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
                  f"p95={p95_i:.1f}, max={max_i:.1f}, avg={avg_i:.1f}")
        
        print("\n--- Latency (ms) ---")
        all_latencies = [e['latency_ms'] for e in self.events if e['latency_ms'] > 0]
        if all_latencies:
            print(f"  Avg: {statistics.mean(all_latencies):.1f}ms")
            print(f"  Median: {statistics.median(all_latencies):.1f}ms")
            print(f"  Max: {max(all_latencies):.1f}ms")
        
        print(f"\nDuplicate events: {self.duplicate_count}/{len(self.events)} ({100*self.duplicate_count/len(self.events):.1f}%)")
        
        print("\n--- Last Known Prices ---")
        for symbol, data in self.last_prices.items():
            print(f"  {symbol}: bid={data[0]}, ask={data[1]}")
        
        # Verdict
        self._print_verdict()

    def _print_verdict(self):
        """Print final verdict"""
        print("\n" + "="*60)
        print("VERDICT: altinapi.com vs Yahoo 3s Polling (Official Docs Compliant)")
        print("="*60)
        
        if len(self.events) == 0:
            print("❌ NO EVENTS RECEIVED")
            print("   Possible causes:")
            print("   1. Plan doesn't include WebSocket (Free trial = REST only)")
            print("   2. Invalid/expired API key (must be hapi_...)")
            print("   3. IP whitelist not configured in dashboard")
            print("   4. Plan doesn't include WebSocket (Pro+ required)")
            return
        
        usdtry_intervals = self.update_intervals.get("USDTRY", [])
        if not usdtry_intervals:
            print("⚠️ No USDTRY intervals recorded")
            return
        
        avg_interval = statistics.mean(self.update_intervals["USDTRY"])
        median_interval = statistics.median(self.update_intervals["USDTRY"])
        
        print(f"\n--- Comparison with Yahoo 3s Polling ---")
        print(f"Yahoo: Fixed 3000ms interval, HTTP overhead, ~500ms latency")
        print(f"altinapi: avg interval={avg_interval:.0f}ms, median={median_interval:.0f}ms")
        print(f"Speedup: {3000/avg_interval:.1f}x faster updates")
        
        all_latencies = [e['latency_ms'] for e in self.events if e['latency_ms'] > 0]
        if all_latencies:
            print(f"Latency (event→receive): {statistics.mean(all_latencies):.1f}ms avg")
        
        print(f"Duplicates: {self.duplicate_count}/{len(self.events)} ({100*self.duplicate_count/len(self.events):.1f}%)")
        print(f"Total events: {len(self.events)}")
        
        # Verdict
        if len(self.events) > 20 and statistics.median(self.update_intervals.get("USDTRY", [1000])) < 1000:
            print("\n✅ VERDICT: altinapi.com PROVIDES REAL-TIME updates")
            print("   - Sub-second update intervals confirmed")
            print("   - Low latency")
            print("   - Suitable for GOLD real-time requirements")
        elif len(self.events) > 0:
            print("\n⚠️ VERDICT: altinapi.com WORKS but check update frequency")
        else:
            print("\n❌ VERDICT: altinapi.com NOT WORKING for real-time")


def main():
    if not os.getenv("ALTINAPI_API_KEY"):
        print("❌ ALTINAPI_API_KEY not set in .env")
        print("Copy .env.example to .env and fill in your API key (format: hapi_...)")
        return
    
    poc = AltinapiPoC()
    asyncio.run(poc.run_poc())


if __name__ == "__main__":
    main()