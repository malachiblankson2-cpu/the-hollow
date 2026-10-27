"""Packs the scripts in src/ into TheHollow.rbxlx, a place file Roblox Studio opens directly.

Run: python3 build.py
"""

from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).parent
SRC = ROOT / "src"

counter = 0


def ref():
    global counter
    counter += 1
    return f"RBX{counter:08d}"


def script(cls, name, filename):
    source = (SRC / filename).read_text()
    assert "]]>" not in source, f"{filename} contains ']]>' which breaks CDATA"
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(name)}</string>'
        f'<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString>'
        f"</Properties></Item>"
    )


def container(cls, children, name=None):
    name = name or cls
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{name}</string></Properties>'
        + "".join(children)
        + "</Item>"
    )


place = (
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
    + container("ReplicatedStorage", [script("ModuleScript", "Config", "Config.lua")])
    + container("ServerScriptService", [script("Script", "GameServer", "GameServer.server.lua")])
    + container(
        "StarterPlayer",
        [container("StarterPlayerScripts", [script("LocalScript", "ClientMain", "ClientMain.client.lua")])],
    )
    + "</roblox>"
)

out = ROOT / "TheHollow.rbxlx"
out.write_text(place)
print(f"Wrote {out}")
