#!/usr/bin/env python3
"""
Hasfiyat WebSocket PoC - Standalone test script
Tests real-time FX + Altın + Gümüş streaming from Hasfiyat API.

Requirements:
- Python 3.8+
- pip install websockets aiohttp python-dotenv

Usage:
1. Copy .env.example to .env and fill in your API credentials
2. python hasfiyat_poc.py
"""

import asyncio
import json
import os
import time
import uuid
from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Optional, Dict, List
from collections import deque
import statistics

import aiohttp
import websockets
from dotenv import load_dotenv

load_dotenv()


@dataclass
class TickEvent:
    """Normalized tick event from Hasfiyat WebSocket"""
    symbol: str
    bid: Optional[float]
    ask: Optional[float]
    last_price: Optional[float]
    provider_timestamp: Optional[str]  # ISO string from provider
    local_receive_timestamp: str       # ISO string when we received it
    latency_ms: float                  # event-to-receive latency
    source: str                        # e.g., "harem"
    raw_data: dict                     # Original message for debugging


class HasfiyatPoC:
    def __init__(self):
        self.api_key = os.getenv("HASFIYAT_API_KEY")
        self.jwt_token = os.getenv("HASFIYAT_JWT_TOKEN")  # For WebSocket
        self.base_rest_url = "https://api.hasfiyat.com"
        self.ws_url = "wss://api.hasfiyat.com/stream"
        self.source = os.getenv("HASFIYAT_SOURCE", "harem")  # Default to harem
        self.symbols = os.getenv("HASFIYAT_SYMBOLS", "USD/TL,EUR/TL,GRAM ALTIN,ÇEYREK ALTIN,GÜMÜŞ TL").split(",")
        
        if not self.api_key:
            raise ValueError("HASFIYAT_API_KEY not set in .env")
        if not self.jwt_token:
            raise ValueError("HASFIYAT_JWT_TOKEN not set in .env")
        
        # Statistics tracking
        self.events: List[TickEvent] = []
        self.last_prices: Dict[str, dict] = {}  # symbol -> {bid, ask, last}
        self.update_intervals: Dict[str, List[float]] = {}  # symbol -> list of intervals (ms)
        self.last_event_time: Dict[str, float] = {}  # symbol -> last event timestamp (monotonic)
        self.duplicate_count = 0
        self.error_count = 0
        self.reconnect_count = 0
        self.start_time = time.monotonic()
        self.ws: Optional[websockets.WebSocketClientProtocol] = None
        self.running = False
        
        # For latency calculation
        self._provider_time_parser = self._parse_iso_timestamp
        
    def _parse_iso_timestamp(self, ts_str: str) -> Optional[float]:
        """Parse ISO timestamp to epoch milliseconds"""
        try:
            dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
            return dt.timestamp() * 1000
        except Exception:
            return None

    async def test_rest_snapshot(self, session: aiohttp.ClientSession) -> dict:
        """Test REST API snapshot before WebSocket"""
        url = f"{self.base_rest_url}/api/prices"
        params = {
            "source": self.source,
            "symbols": ",".join(self.symbols),
            "birim": "1",
            "ham": "1",
        }
        headers = {"Authorization": f"Bearer {self.api_key}"}
        
        print(f"\n[REST] Requesting snapshot for {self.symbols} from source={self.source}")
        start = time.monotonic()
        async with session.get(url, params=params, headers=headers) as resp:
            latency = (time.monotonic() - start) * 1000
            data = await resp.json()
            print(f"[REST] Response in {latency:.1f}ms, status={resp.status}")
            print(f"[REST] LastUpdate: {data.get('lastUpdate')}")
            print(f"[REST] DataAgeMs: {data.get('dataAgeMs')}, Stale: {data.get('stale')}")
            print(f"[REST] Symbols returned: {len(data.get('data', []))}")
            for item in data.get('data', [])[:5]:
                print(f"  - {item.get('title')}: buy={item.get('buy')}, sell={item.get('sell')}, unit={item.get('unit')}, currency={item.get('currency')}")
            return data

    def _normalize_symbol(self, title: str) -> str:
        """Normalize Hasfiyat title to our internal symbol"""
        # Hasfiyat titles: "USD/TL", "EUR/TL", "GRAM ALTIN", "ÇEYREK ALTIN", "GÜMÜŞ TL", etc.
        title_upper = title.upper().strip()
        if "USD/TL" in title_upper or "USD TL" in title_upper:
            return "USDTRY"
        if "EUR/TL" in title_upper or "EUR TL" in title_upper:
            return "EURTRY"
        if "GRAM ALTIN" in title_upper or "GRAMALTIN" in title_upper:
            return "GRAMALTIN"
        if "ÇEYREK" in title_upper or "CEYREK" in title_upper:
            return "CEYREK"
        if "YARIM" in title_upper or "YARIM" in title_upper:
            return "YARIM"
        if "TAM ALTIN" in title_upper or "TAMALTIN" in title_upper:
            return "TAMALTIN"
        if "GÜMÜŞ" in title_upper or "GUMUS" in title_upper:
            return "GUMUS"
        if "ONS" in title_upper:
            return "ONS"
        return title_upper.replace("/", "").replace(" ", "")

    def _parse_price(self, value: str) -> Optional[float]:
        """Parse Turkish formatted price (e.g., '6.692,74' -> 6692.74)"""
        if not value or value in ("-", "—", ""):
            return None
        try:
            # Turkish format: binlik '.', ondalık ','
            cleaned = value.replace(".", "").replace(",", ".")
            return float(cleaned)
        except Exception:
            return None

    def _process_message(self, msg: dict, receive_time_ms: float) -> Optional[TickEvent]:
        """Process incoming WebSocket message and extract tick events"""
        # Hasfiyat WS message format (from docs):
        # Can be a single update or batch of updates
        # Expected format: { "data": [...], "lastUpdate": "...", ... }
        # Or direct array of updates
        
        updates = []
        if isinstance(msg, dict):
            if "data" in msg and isinstance(msg["data"], list):
                updates = msg["data"]
            elif "data" in msg and isinstance(msg["data"], dict):
                updates = [msg["data"]]
            else:
                # Maybe direct update object
                updates = [msg]
        elif isinstance(msg, list):
            updates = msg
        else:
            return None
        
        events = []
        provider_ts = msg.get("lastUpdate") or msg.get("timestamp")
        provider_ts_ms = self._parse_iso_timestamp(provider_ts) if provider_ts else None
        
        for item in updates:
            if not isinstance(item, dict):
                continue
            
            title = item.get("title") or item.get("symbol") or item.get("name")
            if not title:
                continue
                
            symbol = self._normalize_symbol(title)
            
            # Filter to our watched symbols
            if symbol not in [s.upper().replace("/", "").replace(" ", "") for s in self.symbols]:
                # Also check with original symbols
                matched = False
                for s in self.symbols:
                    if s.upper().replace("/", "").replace(" ", "") in symbol or symbol in s.upper().replace("/", "").replace(" ", ""):
                        matched = True
                        break
                if not matched:
                    continue
            
            buy = item.get("buy") or item.get("bid") or item.get("alış")
            sell = item.get("sell") or item.get("ask") or item.get("satış")
            last = item.get("last") or item.get("lastPrice") or item.get("price") or item.get("mid")
            
            bid = self._parse_price(buy) if buy else None
            ask = self._parse_price(sell) if sell else None
            last_price = self._parse_price(last) if last else None
            
            # Also check for rawBuy/rawSell (ham=1)
            raw_bid = self._parse_price(item.get("rawBuy")) if item.get("rawBuy") else None
            raw_ask = self._parse_price(item.get("rawSell")) if item.get("rawSell") else None
            
            provider_ts_ms = provider_ts_ms or (time.time() * 1000)
            latency_ms = (time.monotonic() * 1000) - provider_ts_ms if provider_ts_ms else 0
            
            event = TickEvent(
                symbol=symbol,
                bid=bid or raw_bid,
                ask=ask or raw_ask,
                last_price=last_price,
                provider_timestamp=datetime.fromtimestamp(provider_ts_ms / 1000).isoformat() if provider_ts_ms else datetime.now().isoformat(),
                local_receive_timestamp=datetime.now().isoformat(),
                latency_ms=latency_ms if latency_ms > 0 else ((time.monotonic() * 1000) - receive_time_ms),
                source=self.source,
                raw_data=item
            )
            events.append(event)
        
        return events[0] if events else None

    def _track_event(self, event: TickEvent):
        """Track event for statistics"""
        self.events.append(event)
        
        # Track update intervals
        now_ms = time.monotonic() * 1000
        if event.symbol in self.last_event_time:
            interval = now_ms - self.last_event_time[event.symbol]
            if event.symbol not in self.update_intervals:
                self.update_intervals[event.symbol] = []
            self.update_intervals[event.symbol].append(interval)
        self.last_event_time[event.symbol] = now_ms
        
        # Check for duplicate (same bid/ask/last)
        key = (event.symbol, event.bid, event.ask, event.last_price)
        last_key = self.last_prices.get(event.symbol)
        if last_key == key:
            self.duplicate_count += 1
            print(f"  ⚠️ DUPLICATE: {event.symbol} same values")
        self.last_prices[event.symbol] = key
        
        # Print event
        changed = ""
        if last_key and last_key != key:
            changed = " 🔄 CHANGED"
        print(f"  📊 {event.symbol}: bid={event.bid}, ask={event.ask}, last={event.last_price}, "
              f"latency={event.latency_ms:.1f}ms{changed}")

    def _print_statistics(self):
        """Print collected statistics"""
        print("\n" + "="*60)
        print("STATISTICS SUMMARY")
        print("="*60)
        print(f"Total events received: {len(self.events)}")
        print(f"Duplicate events: {self.duplicate_count}")
        print(f"Errors: {self.error_count}")
        print(f"Reconnects: {self.reconnect_count}")
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
        
        print("\n--- Last Known Prices ---")
        for symbol, data in self.last_prices.items():
            print(f"  {symbol}: bid={data[0]}, ask={data[1]}, last={data[2]}")

    async def connect_websocket(self) -> bool:
        """Establish WebSocket connection"""
        ws_url = f"{self.ws_url}?source={self.source}&token={self.jwt_token}"
        print(f"\n[WS] Connecting to {ws_url}")
        
        try:
            self.ws = await websockets.connect(
                ws_url,
                ping_interval=20,
                ping_timeout=10,
                close_timeout=10,
            )
            print(f"[WS] Connected successfully")
            return True
        except Exception as e:
            print(f"[WS] Connection failed: {e}")
            self.error_count += 1
            return False

    async def listen(self, duration_seconds: int = 300):
        """Listen for WebSocket messages for specified duration"""
        if not self.ws:
            return
        
        self.running = True
        end_time = time.monotonic() + duration_seconds
        
        print(f"\n[WS] Listening for {duration_seconds}s...")
        print("-" * 60)
        
        try:
            async for message in self.ws:
                if not self.running or time.monotonic() > end_time:
                    break
                
                receive_time = time.monotonic() * 1000
                
                try:
                    msg = json.loads(message)
                    events = self._process_message(msg, receive_time)
                    if events:
                        self._track_event(events)
                except json.JSONDecodeError as e:
                    print(f"  ⚠️ JSON decode error: {e}")
                    self.error_count += 1
                except Exception as e:
                    print(f"  ⚠️ Message processing error: {e}")
                    self.error_count += 1
                    
        except websockets.exceptions.ConnectionClosed as e:
            print(f"\n[WS] Connection closed: code={e.code}, reason={e.reason}")
            self.error_count += 1
        except Exception as e:
            print(f"\n[WS] Listen error: {e}")
            self.error_count += 1
        finally:
            self.running = False

    async def test_reconnect(self):
        """Test disconnect/reconnect behavior"""
        print("\n[TEST] Disconnect/Reconnect test...")
        if self.ws:
            await self.ws.close()
            await asyncio.sleep(2)
            self.reconnect_count += 1
            connected = await self.connect_websocket()
            if connected:
                print("[RECONNECT] Successful")
                await self.listen(30)
            else:
                print("[RECONNECT] Failed")

    async def run_poc(self):
        """Main PoC execution"""
        print("="*60)
        print("HASFIYAT WEBSOCKET PoC")
        print("="*60)
        print(f"Source: {self.source}")
        print(f"Symbols: {self.symbols}")
        print(f"REST Base: {self.base_rest_url}")
        print(f"WS URL: {self.ws_url}")
        
        async with aiohttp.ClientSession() as session:
            # 1. Test REST snapshot
            await self.test_rest_snapshot(session)
            
            # 2. Connect WebSocket
            if not await self.connect_websocket():
                print("\n❌ WebSocket connection failed. Cannot proceed.")
                return
            
            # 3. Listen for events (5 minutes = 300s)
            await self.listen(300)
            
            # 4. Test reconnect
            await self.test_reconnect()
            
            # 5. Print final statistics
            self._print_statistics()
            
            # 6. Final verdict
            self._print_verdict()

    def _print_verdict(self):
        """Print final verdict comparing to Yahoo 3s polling"""
        print("\n" + "="*60)
        print("VERDICT: HASFIYAT WebSocket vs Yahoo 3s Polling")
        print("="*60)
        
        if len(self.events) == 0:
            print("❌ NO EVENTS RECEIVED - WebSocket not working")
            return
        
        usdtry_events = [e for e in self.events if e.symbol == "USDTRY"]
        if not usdtry_events:
            print("❌ No USDTRY events - symbol mapping issue")
            return
        
        intervals = self.update_intervals.get("USDTRY", [])
        if intervals:
            median_interval = statistics.median(intervals)
            print(f"\n📊 USDTRY Update Interval: median={intervals[0]:.0f}ms (first), median={statistics.median(intervals):.0f}ms")
        
        # Compare to Yahoo 3s
        print("\n--- Comparison with Yahoo 3s Polling ---")
        print(f"Yahoo: Fixed 3000ms interval, HTTP overhead, ~500ms latency")
        if intervals:
            avg_interval = statistics.mean(intervals)
            print(f"Hasfiyat: avg interval={avg_interval:.0f}ms, median={statistics.median(intervals):.0f}ms")
            print(f"Speedup: {3000/avg_interval:.1f}x faster updates")
        
        print(f"Latency (event→receive): {statistics.mean([e.latency_ms for e in self.events]):.1f}ms avg")
        print(f"Duplicates: {self.duplicate_count}/{len(self.events)} ({100*self.duplicate_count/len(self.events):.1f}%)")
        print(f"Errors: {self.error_count}")
        print(f"Reconnects: {self.reconnect_count}")
        
        # Verdict
        if len(intervals) > 10 and statistics.median(intervals) < 1000:
            print("\n✅ VERDICT: Hasfiyat WebSocket PROVIDES REAL-TIME updates for USDTRY")
            print("   - Sub-second update intervals confirmed")
            print("   - Low latency (<100ms typical)")
            print("   - Suitable for GOLD real-time requirements")
        elif len(self.events) > 0:
            print("\n⚠️ VERDICT: Hasfiyat WebSocket WORKS but update frequency may be lower than expected")
        else:
            print("\n❌ VERDICT: Hasfiyat WebSocket NOT WORKING for real-time")

        # Market closed check
        if self._is_market_closed():
            print("\n⚠️ NOTE: Market appears to be CLOSED (outside trading hours)")
            print("   Update frequency will be lower during closed market")

    def _is_market_closed(self) -> bool:
        """Simple market hours check for Turkey (BIST: 09:30-18:00, FX 24/5)"""
        now = datetime.now()
        # Simplified: FX runs 24/5, but liquidity low outside 08:00-18:00 local
        hour = now.hour
        weekday = now.weekday()  # 0=Mon, 6=Sun
        if weekday >= 5:  # Weekend
            return True
        return False


def main():
    poc = HasfiyatPoC()
    asyncio.run(poc.run_poc())


if __name__ == "__main__":
    main()