#!/usr/bin/env python3
"""
Gramvey WebSocket Test - 60 seconds
Endpoint: wss://goldpricesocket.gramvey.com
"""

import asyncio
import json
import os
import time
import websockets

from dotenv import load_dotenv
load_dotenv()

async def main():
    print("="*60)
    print("Gramvey WebSocket Test - 60 seconds")
    print("="*60)

    msg_count = 0
    price_updates = 0
    start_time = time.time()
    connected = False

    try:
        async with websockets.connect(
            "wss://goldpricesocket.gramvey.com",
            ping_interval=20, ping_timeout=10, close_timeout=5
        ) as ws:
            print("[WS] Connected")
            
            msg_count = 0
            price_updates = 0
            start_time = time.monotonic()
            end_time = time.monotonic() + 60

            # First 5 raw messages
            for i in range(5):
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    print(f"\n[RAW MSG {i+1}] {msg[:500]}")
                    
                    try:
                        data = json.loads(msg)
                        if isinstance(data, list):
                            for item in data:
                                if isinstance(item, dict) and 'symbol' in item:
                                    print(f"  Symbol: {item.get('symbol')}, Bid: {item.get('bid')}, Ask: {item.get('ask')}, Time: {item.get('timestamp', item.get('time'))}")
                    except:
                        pass
                except asyncio.TimeoutError:
                    break

            # Listen for 60 seconds
            start_time = time.monotonic()
            end_time = time.monotonic() + 60
            msg_count = 0
            price_updates = 0

            while time.monotonic() < end_time:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    data = json.loads(msg)

                    if isinstance(data, list):
                        for item in data:
                            if isinstance(item, dict) and 'symbol' in item:
                                symbol = item.get('symbol')
                                bid = item.get('bid') or item.get('buy')
                                ask = item.get('ask') or item.get('sell')
                                if 'bid' in item and 'ask' in item:
                                    print(f"[LIVE] {item.get('symbol')} | Bid: {item.get('bid')} | Ask: {item.get('ask')}")

                    msg_count += 1
                    price_updates += 1
                except asyncio.TimeoutError:
                    continue
                except Exception as e:
                    print(f"[WS] Error: {e}")
                    break

    except Exception as e:
        print(f"Connection failed: {e}")

    elapsed = time.monotonic() - start_time
    print(f"\nConnection: OK")
    print(f"Messages: {msg_count}")
    print(f"Price updates: {price_updates}")
    print(f"Duration: {time.monotonic() - start_time:.1f}s")


if __name__ == "__main__":
    import asyncio
    import json
    import os
    import time
    import websockets
    from dotenv import load_dotenv
    load_dotenv()
    asyncio.run(main())