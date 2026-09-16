import zlib
import struct

def generate_png(size, filename):
    width = height = size
    raw = bytearray()
    bg = (250, 247, 242, 255)       # Luxury vellum #FAF7F2
    gold = (201, 168, 76, 255)      # Antique gold #C9A84C
    charcoal = (42, 36, 33, 255)    # Warm espresso #2A2421
    white = (255, 255, 255, 255)
    cx, cy = width / 2.0, height / 2.0
    r_outer = width * 0.44
    r_inner = width * 0.38
    for y in range(height):
        raw.append(0)  # Filter type None
        for x in range(width):
            dx = x - cx
            dy = y - cy
            dist = (dx * dx + dy * dy) ** 0.5
            if r_inner <= dist <= r_outer:
                raw.extend(gold)
            elif dist < r_inner:
                nx = abs(dx) / (r_inner * 0.72)
                ny = abs(dy) / (r_inner * 0.72)
                if nx + ny <= 1.0:
                    raw.extend(gold)
                elif (dx * dx + dy * dy) <= (width * 0.09) ** 2:
                    raw.extend(charcoal)
                else:
                    raw.extend(white)
            else:
                raw.extend(bg)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png_data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')
    with open(filename, 'wb') as f:
        f.write(png_data)
    print(f"Generated {filename} ({size}x{size})")

if __name__ == '__main__':
    generate_png(180, 'apple-touch-icon.png')
    generate_png(192, 'icon-192.png')
    generate_png(512, 'icon-512.png')
