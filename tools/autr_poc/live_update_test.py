import asyncio
import json
import os
import time
import websockets
from dotenv import load_dotenv

load_dotenv()
key = os.getenv("AUTR_API_KEY")

async def main():
    url = f"wss://autr.tr/ws/prices?api_key={key}"

    async with websockets.connect(url, ping_interval=20, ping_timeout=10) as ws:
        print("CONNECTED")

        msg = await asyncio.wait_for(ws.recv(), 10)
        init = json.loads(msg)

        print("INIT:", init.get("type"))

        prices = {}

        for item in init.get("snapshot", []):
            if isinstance(item, list) and len(item) >= 3:
                idx = int(item[0])
                if idx in (93, 90, 17, 8):
                    prices[idx] = (float(item[1]), float(item[2]))
                    print("START", idx, prices[idx])

        end = time.monotonic() + 600

        while time.monotonic() < end:
            remaining = end - time.monotonic()

            try:
                msg = await asyncio.wait_for(ws.recv(), min(2, remaining))
            except asyncio.TimeoutError:
                continue

            data = json.loads(msg)

            if not isinstance(data, list):
                continue

            for item in data:
                if not isinstance(item, list) or len(item) < 3:
                    continue

                idx = int(item[0])

                if idx not in prices:
                    continue

                bid = float(item[1])
                ask = float(item[2])

                old_bid, old_ask = prices[idx]

                if bid == old_bid and ask == old_ask:
                    continue

                names = {
                    93: "USDTRY",
                    90: "EURTRY",
                    17: "CEYREK_YENI",
                    8: "GUMUSTRY",
                }

                print(
                    "LIVE",
                    names[idx],
                    old_bid,
                    "->",
                    bid,
                    "|",
                    old_ask,
                    "->",
                    ask,
                )

                prices[idx] = (bid, ask)

        print("TEST FINISHED")

asyncio.run(main())