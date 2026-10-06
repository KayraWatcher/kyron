#!/usr/bin/env python3
"""
AuTR parite_idx to symbol Auto-Mapper
Matches WS INIT snapshot to REST prices using multi-criteria matching
"""

import asyncio
import json
import os
from datetime import datetime
from typing import Dict, List, Tuple, Set

import aiohttp
import websockets
from dotenv import load_dotenv

load_dotenv()

API_KEY = os.getenv("AUTR_API_KEY")
if not API_KEY:
    raise ValueError("AUTR_API_KEY not set in .env")


def evaluate_match(rest_alis: float, rest_satis: float, 
                   ws_alis: float, ws_satis: float) -> Tuple[str, float]:
    """Evaluate match quality between REST and WS prices"""
    if rest_alis <= 0 or rest_satis <= 0 or ws_alis <= 0 or ws_satis <= 0:
        return "UNKNOWN", 0.0
    
    alis_diff = abs(rest_alis - ws_alis) / rest_alis
    satis_diff = abs(rest_satis - ws_satis) / rest_satis
    ratio_diff = abs((rest_alis/rest_satis) - (ws_alis/ws_satis)) / (rest_alis/rest_satis)
    
    max_diff = max(alis_diff, satis_diff)
    ratio_diff = abs((rest_alis/rest_satis) - (ws_alis/ws_satis)) / (rest_alis/rest_satis)
    
    score = 1.0 - (0.4 * alis_diff + 0.4 * satis_diff + 0.2 * ratio_diff)
    score = max(0.0, min(1.0, score))
    
    max_diff = max(abs(rest_alis - ws_alis)/rest_alis, abs(rest_satis - ws_satis)/rest_satis)
    
    if max_diff <= 0.005 and abs((rest_alis/rest_satis) - (ws_alis/ws_satis)) / (rest_alis/rest_satis) <= 0.005:
        return "HIGH", 1.0 - max_diff
    elif max_diff <= 0.02:
        return "MEDIUM", 1.0 - max_diff
    elif max_diff <= 0.05:
        return "LOW", 1.0 - max_diff
    else:
        return "UNKNOWN", 0.0


async def fetch_rest_prices() -> Dict:
    """Fetch all prices from REST API"""
    async with aiohttp.ClientSession() as session:
        async with session.get(
            "https://autr.tr/api/prices/live",
            headers={"X-API-Key": os.getenv("AUTR_API_KEY")}
        ) as resp:
            if resp.status != 200:
                raise Exception(f"REST error {resp.status}")
            data = await resp.json()
            return data.get('data', data.get('prices', {}))


async def fetch_ws_snapshot() -> list:
    """Fetch WS INIT snapshot"""
    async with websockets.connect(
        f"wss://autr.tr/ws/prices?api_key={os.getenv('AUTR_API_KEY')}",
        ping_interval=20, ping_timeout=10
    ) as ws:
        msg = await ws.recv()
        data = json.loads(msg)
        if data.get('type') != 'init':
            raise Exception(f"Expected INIT, got: {msg[:200]}")
        return data.get('snapshot', [])


def find_matches(rest_prices: dict, ws_snapshot: list) -> dict:
    """Find best matches between REST prices and WS snapshot"""
    
    # Build REST items list (all symbols with valid prices)
    rest_items = []
    for sym, item in rest_prices.items():
        alis = item.get('alis')
        satis = item.get('satis')
        if alis and satis:
            rest_items.append({
                'symbol': sym,
                'alis': float(alis),
                'satis': float(satis),
            })
    
    # Parse WS snapshot
    ws_items = []
    for item in ws_snapshot:
        if isinstance(item, list) and len(item) >= 3:
            parite_idx = int(item[0])
            alis = float(item[1])
            satis = float(item[2])
            ws_items.append({
                'parite_idx': parite_idx,
                'alis': alis,
                'satis': satis,
            })
    
    print(f"[MATCH] REST items: {len(rest_items)}, WS items: {len(ws_items)}")
    
    # Match each WS item to best REST symbol
    matches = {}
    used_symbols: Set[str] = set()
    
    for ws_item in ws_items:
        candidates = []
        for rest_item in rest_items:
            if rest_item['symbol'] in used_symbols:
                continue
            conf, score = evaluate_match(
                rest_item['alis'], rest_item['satis'],
                ws_item['alis'], ws_item['satis']
            )
            if conf != "UNKNOWN":
                candidates.append((rest_item['symbol'], conf, score, rest_item))
        
        if not candidates:
            continue
        
        # Sort by score descending
        candidates.sort(key=lambda x: x[2], reverse=True)
        best = candidates[0]
        
        # Check for ambiguity
        if len(candidates) > 1:
            second_best = candidates[1]
            score_diff = best[2] - second_best[2]
            if score_diff < 0.01:
                print(f"  [AMBIGUOUS] parite_idx={ws_item['parite_idx']}: {best[0]} ({best[2]:.4f}) vs {second_best[0]} ({second_best[2]:.4f})")
                continue
        
        # Found unique best match
        matches[ws_item['parite_idx']] = {
            'symbol': best[0],
            'confidence': best[1],
            'score': best[2],
            'ws_alis': ws_item['alis'],
            'ws_satis': ws_item['satis'],
        }
    
    return matches


async def main():
    import os
    import asyncio
    import json
    from datetime import datetime
    from typing import Dict, List, Tuple, Set
    import aiohttp
    import websockets
    from dotenv import load_dotenv
    
    load_dotenv()
    
    print("="*60)
    print("AuTR parite_idx â†’ symbol Auto-Mapper")
    print("="*60)
    
    # 1. Fetch REST prices
    print("\n[1] Fetching REST prices...")
    async with aiohttp.ClientSession() as session:
        async with session.get(
            "https://autr.tr/api/prices/live",
            headers={"X-API-Key": os.getenv("AUTR_API_KEY")}
        ) as resp:
            if resp.status != 200:
                raise Exception(f"REST error {resp.status}")
            data = await resp.json()
            rest_prices = data.get('data', data.get('prices', {}))
    
    print(f"   Total symbols: {len(rest_prices)}")
    
    # 2. Fetch WS INIT snapshot
    print("\n[2] Fetching WS INIT snapshot...")
    async with websockets.connect(
        f"wss://autr.tr/ws/prices?api_key={os.getenv('AUTR_API_KEY')}",
        ping_interval=20, ping_timeout=10
    ) as ws:
        msg = await ws.recv()
        data = json.loads(msg)
        if data.get('type') != 'init':
            raise Exception(f"Expected INIT, got: {msg[:200]}")
        ws_snapshot = data.get('snapshot', [])
    
    print(f"[WS] INIT snapshot: {len(ws_snapshot)} items")
    
    # Debug: show first 5 items
    for i, item in enumerate(ws_snapshot[:5]):
        print(f"  snapshot[{i}]: {item}")
    
    # Parse WS snapshot
    ws_items = []
    for item in ws_snapshot:
        if isinstance(item, list) and len(item) >= 3:
            parite_idx = int(item[0])
            alis = float(item[1])
            satis = float(item[2])
            ws_items.append({
                'parite_idx': parite_idx,
                'alis': alis,
                'satis': satis,
            })
    
    print(f"[WS] Parsed {len(ws_items)} valid items")
    
    # Build REST list
    rest_items = []
    async with aiohttp.ClientSession() as session:
        async with session.get(
            "https://autr.tr/api/prices/live",
            headers={"X-API-Key": os.getenv("AUTR_API_KEY")}
        ) as resp:
            data = await resp.json()
            prices = data.get('data', data.get('prices', {}))
            for sym, item in prices.items():
                alis = item.get('alis')
                satis = item.get('satis')
                if alis and satis:
                    rest_items.append({
                        'symbol': sym,
                        'alis': float(alis),
                        'satis': float(satis),
                    })
    
    print(f"[REST] Parsed {len(rest_items)} items with valid prices")
    
    # Match
    print("\n[MATCHING] Finding best matches...")
    
    # Build rest_items list for matching function
    rest_items_for_match = []
    async with aiohttp.ClientSession() as session:
        async with session.get(
            "https://autr.tr/api/prices/live",
            headers={"X-API-Key": os.getenv("AUTR_API_KEY")}
        ) as resp:
            data = await resp.json()
            prices = data.get('data', data.get('prices', {}))
            rest_items = []
            for sym, item in prices.items():
                alis = item.get('alis')
                satis = item.get('satis')
                if alis and satis:
                    rest_items.append({
                        'symbol': sym,
                        'alis': float(alis),
                        'satis': float(satis),
                    })
    
    # Match
    print("\n[MATCHING] Finding best matches...")
    
    matches = {}
    used_symbols: Set[str] = set()
    
    for ws_item in ws_items:
        candidates = []
        for rest_item in rest_items:
            if rest_item['symbol'] in used_symbols:
                continue
            conf, score = evaluate_match(
                rest_item['alis'], rest_item['satis'],
                ws_item['alis'], ws_item['satis']
            )
            if conf != "UNKNOWN":
                candidates.append((rest_item['symbol'], conf, score, rest_item))
        
        if not candidates:
            continue
        
        candidates.sort(key=lambda x: x[2], reverse=True)
        best = candidates[0]
        
        if len(candidates) > 1:
            second_best = candidates[1]
            score_diff = best[2] - second_best[2]
            if score_diff < 0.01:
                print(f"  [AMBIGUOUS] parite_idx={ws_item['parite_idx']}: {best[0]} ({best[2]:.4f}) vs {second_best[0]} ({second_best[2]:.4f})")
                continue
        
        matches[ws_item['parite_idx']] = {
            'symbol': best[0],
            'confidence': best[1],
            'score': best[2],
            'ws_alis': ws_item['alis'],
            'ws_satis': ws_item['satis'],
        }
        used_symbols.add(best[0])
    
    # Report
    high = sum(1 for v in matches.values() if v['confidence'] == 'HIGH')
    medium = sum(1 for v in matches.values() if v['confidence'] == 'MEDIUM')
    low = sum(1 for v in matches.values() if v['confidence'] == 'LOW')
    unknown = len(ws_items) - len(matches)
    
    print(f"\n=== MATCHING RESULTS ===")
    print(f"HIGH confidence: {high}")
    print(f"MEDIUM confidence: {medium}")
    print(f"LOW confidence: {low}")
    print(f"UNKNOWN/NO MATCH: {len(ws_items) - len(matches)}")
    print(f"Total WS items: {len(ws_items)}")
    print(f"Matched: {len(matches)}")
    
    # Target symbols
    print("\n--- TARGET SYMBOLS ---")
    target_symbols = ["USDTRY", "EURTRY", "GRAMALTIN", "CEYREK_YENI", "GUMUSTRY"]
    for sym in ["USDTRY", "EURTRY", "GRAMALTIN", "CEYREK_YENI", "GUMUSTRY"]:
        found = False
        for idx, m in matches.items():
            if m['symbol'] == sym:
                print(f"\n{sym}:")
                print(f"  parite_idx: {idx}")
                print(f"  Confidence: {m['confidence']}")
                print(f"  WS: alis={m['ws_alis']}, satis={m['ws_satis']}")
                # Find REST price for comparison
                for item in ws_items:
                    if item['parite_idx'] == idx:
                        break
                # Find REST price
                for sym_data in [s for s in ws_items if s['parite_idx'] == idx]:
                    pass
                # We need REST price for comparison
                rest_price = None
                async with aiohttp.ClientSession() as session:
                    async with session.get(
                        "https://autr.tr/api/prices/live",
                        headers={"X-API-Key": os.getenv("AUTR_API_KEY")}
                    ) as resp:
                        data = await resp.json()
                        prices = data.get('data', data.get('prices', {}))
                        if sym in prices:
                            p = prices[sym]
                            rest_alis = p.get('alis')
                            rest_satis = p.get('satis')
                            if rest_alis and rest_satis:
                                alis_diff = abs(rest_alis - m['ws_alis']) / rest_alis * 100
                                satis_diff = abs(rest_satis - m['ws_satis']) / rest_satis * 100
                                print(f"  REST: alis={rest_alis}, satis={rest_satis}")
                                print(f"  WS:   alis={m['ws_alis']}, satis={m['ws_satis']}")
                                print(f"  Diff: alis={alis_diff:.2f}%, satis={satis_diff:.2f}%")
                break
        else:
            print(f"\n{sym}: NO MATCH FOUND")
    
    # Save mapping
    mapping_file = f"autr_parite_idx_mapping_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    clean_mapping = {str(k): v['symbol'] for k, v in matches.items() 
                     if v['confidence'] in ['HIGH', 'MEDIUM']}
    with open(mapping_file, 'w') as f:
        json.dump(clean_mapping, f, indent=2)
    print(f"\n[SAVED] Mapping saved to: {mapping_file}")
    
    # Summary
    high = sum(1 for v in matches.values() if v['confidence'] == 'HIGH')
    medium = sum(1 for v in matches.values() if v['confidence'] == 'MEDIUM')
    low = sum(1 for v in matches.values() if v['confidence'] == 'LOW')
    unknown = len(ws_items) - len(matches)
    
    print(f"\n=== SUMMARY ===")
    print(f"HIGH: {high}")
    print(f"MEDIUM: {medium}")
    print(f"LOW: {low}")
    print(f"UNKNOWN: {len(ws_items) - len(matches)}")
    print(f"Mapping saved to: {mapping_file}")

if __name__ == "__main__":
    import os
    import asyncio
    import json
    from datetime import datetime
    from typing import Dict, List, Tuple, Set
    import aiohttp
    import websockets
    from dotenv import load_dotenv
    
    load_dotenv()
    asyncio.run(main())
