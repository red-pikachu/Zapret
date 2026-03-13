import urllib.request
import json
import re

URL = "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/general.bat"
print("Fetching latest general.bat from Flowseal...")

req = urllib.request.Request(URL)
try:
    with urllib.request.urlopen(req) as response:
        content = response.read().decode('utf-8')
except Exception as e:
    print(f"Error fetching script: {e}")
    exit(1)

strategies = []
lines = content.split('^')
for idx, line in enumerate(lines):
    line = line.strip()
    if not line or line.startswith('::') or line.startswith('@'): continue
    
    if '--dpi-desync=' in line:
        desync_arg = ""
        if 'fake' in line and 'multisplit' not in line:
            desync_arg = "--lua-desync=desync:desync=fake"
            if '--dpi-desync-repeats=' in line:
                repeats = re.search(r'--dpi-desync-repeats=(\d+)', line)
                if repeats: desync_arg += f";repeats={repeats.group(1)}"
            desync_arg += ";fake_type=tls_clienthello"
            
        elif 'multisplit' in line:
            desync_arg = "--lua-desync=desync:desync=multisplit"
            if '--dpi-desync-split-seqovl=' in line:
                val = re.search(r'--dpi-desync-split-seqovl=(\d+)', line)
                if val: desync_arg += f";split_seqovl={val.group(1)}"
            if '--dpi-desync-split-pos=' in line:
                val = re.search(r'--dpi-desync-split-pos=(\d+)', line)
                if val: desync_arg += f";split_pos={val.group(1)}"
                
        name = f"Flowseal Auto Extracted #{idx}"
        if 'discord' in line.lower() or '19294' in line: name = f"Flowseal Discord Auto"
        if '80,443' in line: name = f"Flowseal General Auto"
        
        if desync_arg:
            strategies.append({
                "id": f"flowseal_auto_{idx}",
                "name": name,
                "args": desync_arg
            })

try:
    with open('strategies.json', 'r') as f:
        current = json.load(f)
except:
    current = []

# Remove old auto-extracted
current = [s for s in current if not s['id'].startswith('flowseal_auto_')]

# Append new
current.extend(strategies)

with open('strategies.json', 'w') as f:
    json.dump(current, f, indent=2)

print(f"Successfully extracted {len(strategies)} strategies and updated strategies.json.")
