"""Create the single release illustration from offscreen native app views."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
source = root / '.build/release-scenarios'
image = Image.open(source / '02-context-preview.png').convert('RGB')
scale = image.width / 1600
image = image.crop((0, 0, image.width, round(888 * scale)))
draw = ImageDraw.Draw(image)
panel = json.loads((source / '02-context-panel.json').read_text())
rectangles = [
    (508, 1, 1332, 35),
    (panel['x'] - 4, panel['y'] - 4,
     panel['x'] + panel['width'] + 4, panel['y'] + panel['height'] + 4),
]
for i, rect in enumerate(rectangles):
    draw.rounded_rectangle(tuple(round(v * scale) for v in rect),
                           radius=round((4 if i == 0 else 15) * scale),
                           outline='#F04444', width=round(2.5 * scale))
destination = root / 'Assets/usage-preview.png'
destination.parent.mkdir(exist_ok=True)
image.save(destination, optimize=True)
print(destination)
