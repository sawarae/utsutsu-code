#!/usr/bin/env python3
"""
Mascot Position Detector

Detects つくよみちゃん mascot position in screenshots using PIL.
Provides accurate pixel-level detection instead of unreliable visual analysis.
"""

from PIL import Image
import json
import sys
from pathlib import Path
from collections import defaultdict


class MascotDetector:
    """Detect mascot character position in screenshots."""

    def __init__(self, image_path: str):
        """Initialize detector with screenshot path."""
        self.image_path = Path(image_path)
        self.image = Image.open(self.image_path)
        self.width, self.height = self.image.size
        self.pixels = self.image.load()

        print(f"[INFO] Image loaded: {self.width}x{self.height}", file=sys.stderr)

    def is_white_pixel(self, r, g, b):
        """Check if pixel is white (high RGB values, low saturation)."""
        # White pixels have high values and similar RGB components
        min_brightness = 200
        max_color_diff = 30

        if r < min_brightness or g < min_brightness or b < min_brightness:
            return False

        color_diff = max(r, g, b) - min(r, g, b)
        return color_diff < max_color_diff

    def detect_white_regions(self):
        """
        Detect white regions (mascots) using connected component analysis.

        Returns:
            List of detected mascot bounding boxes: [(x, y, w, h), ...]
        """
        # Create binary mask for white pixels
        white_mask = {}
        for y in range(self.height):
            for x in range(self.width):
                pixel = self.pixels[x, y]
                if len(pixel) >= 3:  # RGB or RGBA
                    r, g, b = pixel[:3]
                    if self.is_white_pixel(r, g, b):
                        white_mask[(x, y)] = True

        print(f"[INFO] Found {len(white_mask)} white pixels", file=sys.stderr)

        # Find connected components (simple flood fill approach)
        visited = set()
        regions = []

        def flood_fill(start_x, start_y):
            """Flood fill to find connected white region."""
            stack = [(start_x, start_y)]
            region_pixels = []

            while stack:
                x, y = stack.pop()

                if (x, y) in visited or (x, y) not in white_mask:
                    continue

                visited.add((x, y))
                region_pixels.append((x, y))

                # Check 4-connected neighbors
                for dx, dy in [(0, 1), (0, -1), (1, 0), (-1, 0)]:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.width and 0 <= ny < self.height:
                        if (nx, ny) in white_mask and (nx, ny) not in visited:
                            stack.append((nx, ny))

            return region_pixels

        # Find all connected regions
        for (x, y) in white_mask:
            if (x, y) not in visited:
                region = flood_fill(x, y)
                if len(region) > 500:  # Minimum region size
                    regions.append(region)

        print(f"[INFO] Found {len(regions)} white regions", file=sys.stderr)

        # Convert regions to bounding boxes
        mascots = []
        for region in regions:
            xs = [p[0] for p in region]
            ys = [p[1] for p in region]

            x_min, x_max = min(xs), max(xs)
            y_min, y_max = min(ys), max(ys)

            w = x_max - x_min + 1
            h = y_max - y_min + 1
            area = len(region)

            # Filter by aspect ratio (mascot is roughly vertical)
            aspect_ratio = h / w if w > 0 else 0

            # Filter by size and aspect ratio
            if area > 1000 and 1.5 < aspect_ratio < 5.0:
                mascots.append((x_min, y_min, w, h, area))

        return mascots

    def analyze_position(self, bbox):
        """
        Analyze mascot position as percentages.

        Args:
            bbox: Bounding box (x, y, w, h, area)

        Returns:
            dict: Position analysis
        """
        x, y, w, h, area = bbox

        # Calculate positions
        left_x = x
        right_x = x + w
        top_y = y
        bottom_y = y + h
        center_x = x + w // 2
        center_y = y + h // 2

        # Calculate percentages
        left_pct = (left_x / self.width) * 100
        right_pct = (right_x / self.width) * 100
        top_pct = (top_y / self.height) * 100
        bottom_pct = (bottom_y / self.height) * 100
        center_x_pct = (center_x / self.width) * 100
        center_y_pct = (center_y / self.height) * 100

        return {
            "image_size": {"width": self.width, "height": self.height},
            "bounding_box": {
                "x": int(x),
                "y": int(y),
                "width": int(w),
                "height": int(h),
                "area": int(area)
            },
            "position_px": {
                "left": int(left_x),
                "right": int(right_x),
                "top": int(top_y),
                "bottom": int(bottom_y),
                "center_x": int(center_x),
                "center_y": int(center_y),
            },
            "position_pct": {
                "left": round(left_pct, 2),
                "right": round(right_pct, 2),
                "top": round(top_pct, 2),
                "bottom": round(bottom_pct, 2),
                "center_x": round(center_x_pct, 2),
                "center_y": round(center_y_pct, 2),
            },
        }

    def detect_and_analyze(self):
        """Detect all mascots and analyze their positions."""
        mascots = self.detect_white_regions()

        if not mascots:
            return {"error": "No mascots detected", "mascots": []}

        results = []
        for i, bbox in enumerate(mascots):
            analysis = self.analyze_position(bbox)
            analysis["mascot_id"] = i
            results.append(analysis)

        # Sort by area (largest first = likely parent mascot)
        results.sort(
            key=lambda x: x["bounding_box"]["area"],
            reverse=True
        )

        return {"mascots": results, "count": len(results)}


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: mascot_detector.py <screenshot_path>", file=sys.stderr)
        sys.exit(1)

    image_path = sys.argv[1]

    try:
        detector = MascotDetector(image_path)
        results = detector.detect_and_analyze()

        # Output JSON
        print(json.dumps(results, indent=2))

    except Exception as e:
        import traceback
        print(json.dumps({"error": str(e), "traceback": traceback.format_exc()}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
