#!/usr/bin/env python3
"""
AuTR WebSocket Diagnostic - 60 seconds
Investigates message flow after INIT
"""

import asyncio
import json
import os
import time
import websockets
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")


async def main():
    print("="*60)
    print("AuTR WebSocket Diagnostic - 60 seconds")
    print("="*60)

    try:
        async with websockets.connect(
            f"wss://autr.tr/ws/prices?api_key={os.getenv('AUTR_API_KEY')}",
            ping_interval=20, ping_timeout=10, close_timeout=5
        ) as ws:
            print("[WS] Connected")

            # INIT
            init_msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
            init_data = json.loads(init_msg)

            print(f"\nINIT type: {init_data.get('type')}")
            
            for key in ['timestamp', 'server_time', 'updated_at', 'time', 'serverTime', 'timestamp_ms']:
                if key in init_data:
                    print(f"  INIT.{key} = {init_data[key]}")

            snapshot = init_data.get("snapshot", [])
            snapshot_count = len(snapshot)
            print(f"Snapshot count: {snapshot_count}")

            print("\nSnapshot symbols:")
            for item in snapshot:
                if isinstance(item, list) and len(item) >= 3:
                    idx = int(item[0])
                    alis = float(item[1])
                    satis = float(item[2])
                    print(f"  idx={idx:3d}  alis={alis:>10.2f}  satis={satis:>10.2f}")

            if 'timestamp' in init_data:
                print(f"\nINIT timestamp: {init_data['timestamp']}")
            
            print("\n[WS] Listening for messages (60s)...")
            print("-" * 50)

            msg_count = 0
            price_changes = 0
            other_msgs = 0
            start_time = time.monotonic()
            end_time = time.monotonic() + 60

            last_prices = {}
            for item in init_data.get("snapshot", []):
                if isinstance(item, list) and len(item) >= 3:
                    parite_idx = int(item[0])
                    if parite_idx in [93, 90, 17, 8]:
                        last_prices[parite_idx] = (float(item[1]), float(item[2]))

            while time.monotonic() < end_time:
                try:
                    msg = await asyncio.wait_for(ws.recv(), timeout=2.0)
                    data = json.loads(msg)
                    
                    if data.get("type") == "init":
                        print("  [WS] Re-init received")
                        continue

                    msg_count = msg_count + 1 if 'msg_count' in locals() else 1
                    msg_count = msg_count + 1

                    if isinstance(data, list):
                        price_changed = False
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
                                    continue

                                change_alis = new_alis - old_alis
                                change_satis = new_satis - old_satis
                                change_pct = ((new_alis - old_alis) / old_alis * 100) if old_alis else 0

                                print(f"  [UPDATE] idx={update[0]} alis={old_alis}->{new_alis} satis={old_satis}->{new_satis} diff={change_pct:+.4f}%")
                                price_changes = price_changes + 1 if 'price_changes' in locals() else 1
                                
                                last_prices[parite_idx] = (float(update[1]), float(update[2]))
                                price_changed = True
                        
                        if price_changed:
                            price_changes = price_changes + 1 if 'price_changes' in locals() else 1
                        else:
                            pass
                    else:
                        other_msgs = other_msgs + 1 if 'other_msgs' in locals() else 1
                        print(f"  [MSG] type=dict keys={list(data.keys())}")

                except asyncio.TimeoutError:
                    continue
                except websockets.exceptions.ConnectionClosed as e:
                    print(f"[WS] Connection closed: code={e.code}")
                    break
                except Exception as e:
                    print(f"[WS] Error: {e}")

            except asyncio.TimeoutError:
                pass
            except websockets.exceptions.ConnectionClosed as e:
                print(f"[WS] Connection closed: code={e.code}")
            except Exception as e:
                print(f"[WS] Error: {e}")

        finally:
            elapsed = time.monotonic() - start_time
            print("\n" + "="*50)
            print("DIAGNOSTIC SUMMARY")
            print("="*50)
            print(f"Connection: OK")
            print(f"INIT: OK")
            print(f"Snapshot count: {snapshot_count}")
            print(f"Messages after INIT: {msg_count}")
            print(f"Price-changing messages: {price_changes if 'price_changes' in locals() else 0}")
            print(f"Other messages: {other_msgs if 'other_msgs' in locals() else 0}")
            print(f"Test duration: {elapsed:.1f}s")


if __name__ == "__main__":
    import os
    import asyncio
    import json
    import time
    import websockets
    from dotenv import load_dotenv
    load_dotenv()

    API_KEY = os.getenv("AUTR_API_KEY")
    if not API_KEY:
        raise ValueError("AUTR_API_KEY not set in .env")

    asyncio.run(main())