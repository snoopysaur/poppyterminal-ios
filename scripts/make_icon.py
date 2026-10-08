"""Gera o AppIcon 1024x1024 (nearest-neighbor, fundo Catppuccin Mocha base)."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
src = Image.open(root / "master64.png").convert("RGBA")
scale = 1024 // src.width  # 16x
big = src.resize((src.width * scale, src.height * scale), Image.NEAREST)
bg = Image.new("RGBA", (1024, 1024), (0x1E, 0x1E, 0x2E, 255))
bg.alpha_composite(big, ((1024 - big.width) // 2, (1024 - big.height) // 2))
out = root.parent / "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
bg.convert("RGB").save(out)  # sem alpha: exigencia da App Store
print("ok", out)
