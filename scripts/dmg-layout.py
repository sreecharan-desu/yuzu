"""Writes the Finder layout (.DS_Store) for a mounted Yuzu disk image without scripting Finder.
Usage: python scripts/dmg-layout.py /Volumes/Yuzu"""
import os
import sys

from ds_store import DSStore
from mac_alias import Alias

vol = sys.argv[1]
bg = os.path.join(vol, ".background", "background.tiff")
alias = Alias.for_file(bg)

with DSStore.open(os.path.join(vol, ".DS_Store"), "w+") as d:
    d["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowToolbar": False, "ShowTabView": False, "ShowPathbar": False,
        "ShowSidebar": False, "SidebarWidth": 0, "WindowBounds": "{{200, 160}, {660, 422}}",
    }
    d["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 2, "backgroundImageAlias": alias.to_bytes(),
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "iconSize": 112.0, "textSize": 13.0, "gridSpacing": 100.0, "gridOffsetX": 0.0, "gridOffsetY": 0.0,
        "labelOnBottom": True, "showIconPreview": True, "showItemInfo": False,
        "arrangeBy": "none", "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    }
    d["."]["vSrn"] = ("long", 1)
    d["Yuzu.app"]["Iloc"] = (170, 200)
    d["Applications"]["Iloc"] = (490, 200)
print("layout written to", vol)
