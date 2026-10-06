using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace Half {
        public uint16 from_float (float f) {
            uint32 x = *((uint32*) (&f));
            uint32 sign = (x >> 16) & 0x8000;
            int exp = (int) ((x >> 23) & 0xff) - 127 + 15;
            uint32 mant = x & 0x7fffff;
            if (((x >> 23) & 0xff) == 0xff) return (uint16) (sign | 0x7c00 | (mant != 0 ? 0x200 : 0));
            if (exp >= 31) return (uint16) (sign | 0x7c00);
            if (exp <= 0) {
                if (exp < -10) return (uint16) sign;
                mant |= 0x800000;
                int shift = 14 - exp;
                uint32 half_mant = mant >> shift;
                if (((mant >> (shift - 1)) & 1) != 0) half_mant++;
                return (uint16) (sign | half_mant);
            }
            uint32 r = sign | ((uint32) exp << 10) | (mant >> 13);
            if ((mant & 0x1000) != 0) r++;
            return (uint16) r;
        }

        public float to_float (uint16 h) {
            uint32 sign = ((uint32) h & 0x8000) << 16;
            uint32 exp = ((uint32) h >> 10) & 0x1f;
            uint32 mant = (uint32) h & 0x3ff;
            uint32 bits;
            if (exp == 0) {
                if (mant == 0) bits = sign;
                else {
                    int e = -1;
                    do {
                        e++;
                        mant <<= 1;
                    } while ((mant & 0x400) == 0);
                    mant &= 0x3ff;
                    bits = sign | ((uint32) (127 - 15 - e) << 23) | (mant << 13);
                }
            } else if (exp == 31) {
                bits = sign | 0x7f800000 | (mant << 13);
            } else {
                bits = sign | ((exp + 127 - 15) << 23) | (mant << 13);
            }
            return *((float*) (&bits));
        }
    }

    namespace Exr {
        private class Reader {
            public unowned uint8[] d;
            public size_t pos = 0;

            public Reader (uint8[] d) {
                this.d = d;
            }

            public uint32 u32 () throws Error {
                if (pos + 4 > d.length) throw new ImageError.FORMAT ("Truncated EXR");
                uint32 v = (uint32) d[pos] | ((uint32) d[pos + 1] << 8) | ((uint32) d[pos + 2] << 16) | ((uint32) d[pos + 3] << 24);
                pos += 4;
                return v;
            }

            public uint64 u64 () throws Error {
                uint64 lo = u32 ();
                uint64 hi = u32 ();
                return lo | (hi << 32);
            }

            public string cstr () throws Error {
                var sb = new StringBuilder ();
                while (pos < d.length && d[pos] != 0) sb.append_c ((char) d[pos++]);
                if (pos >= d.length) throw new ImageError.FORMAT ("Truncated EXR header");
                pos++;
                return sb.str;
            }
        }

        private class Channel {
            public string name;
            public int type;
        }

        public FloatImage decode (uint8[] data) throws Error {
            var r = new Reader (data);
            if (r.u32 () != 20000630) throw new ImageError.FORMAT ("Not an OpenEXR file");
            uint32 version = r.u32 ();
            if ((version & 0x200) != 0) throw new ImageError.UNSUPPORTED ("Tiled OpenEXR files are not supported");
            var channels = new Gee.ArrayList<Channel> ();
            int compression = 0;
            int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
            while (true) {
                var name = r.cstr ();
                if (name == "") break;
                var type = r.cstr ();
                uint32 size = r.u32 ();
                size_t end = r.pos + size;
                if (name == "channels" && type == "chlist") {
                    while (r.pos < end - 1) {
                        var c = new Channel ();
                        c.name = r.cstr ();
                        c.type = (int) r.u32 ();
                        r.pos += 12;
                        channels.add (c);
                    }
                } else if (name == "compression") {
                    compression = r.d[r.pos];
                } else if (name == "dataWindow") {
                    x0 = (int) r.u32 ();
                    y0 = (int) r.u32 ();
                    x1 = (int) r.u32 ();
                    y1 = (int) r.u32 ();
                }
                r.pos = end;
            }
            int w = x1 - x0 + 1, h = y1 - y0 + 1;
            if (w <= 0 || h <= 0 || w > 32768 || h > 32768) throw new ImageError.FORMAT ("Bad EXR size");
            int lines_per_block = compression == 3 ? 16 : (compression == 4 ? 32 : 1);
            if (compression > 3) throw new ImageError.UNSUPPORTED ("OpenEXR compression %d is not supported", compression);
            int blocks = (h + lines_per_block - 1) / lines_per_block;
            var offsets = new uint64[blocks];
            for (int i = 0; i < blocks; i++) offsets[i] = r.u64 ();
            size_t line_bytes = 0;
            foreach (var c in channels) line_bytes += (size_t) w * (c.type == 1 ? 2 : 4);
            var img = new FloatImage (w, h);
            bool has_alpha = false;
            foreach (var c in channels) if (c.name == "A") has_alpha = true;
            if (!has_alpha) img.fill (0, 0, 0, 1);
            for (int b = 0; b < blocks; b++) {
                r.pos = (size_t) offsets[b];
                int y = (int) r.u32 () - y0;
                uint32 size = r.u32 ();
                if (r.pos + size > data.length) throw new ImageError.FORMAT ("Truncated EXR block");
                int lines = int.min (lines_per_block, h - y);
                size_t expected = line_bytes * lines;
                uint8[] block = data[r.pos:r.pos + size];
                uint8[] raw;
                if (compression == 0 || size == expected) raw = block;
                else if (compression == 1) raw = unrle (block, expected);
                else raw = unpredict (ImageIO.inflate_zlib (block, expected));
                if (raw.length < expected) throw new ImageError.FORMAT ("Bad EXR block");
                size_t p = 0;
                for (int ly = 0; ly < lines; ly++) {
                    foreach (var c in channels) {
                        int ch = c.name == "R" ? 0 : (c.name == "G" ? 1 : (c.name == "B" ? 2 : (c.name == "A" ? 3 : (c.name == "Y" ? 4 : -1))));
                        for (int x = 0; x < w; x++) {
                            float v;
                            if (c.type == 1) {
                                v = Half.to_float ((uint16) (raw[p] | (raw[p + 1] << 8)));
                                p += 2;
                            } else if (c.type == 2) {
                                uint32 bits = (uint32) raw[p] | ((uint32) raw[p + 1] << 8) | ((uint32) raw[p + 2] << 16) | ((uint32) raw[p + 3] << 24);
                                v = *((float*) (&bits));
                                p += 4;
                            } else {
                                uint32 u = (uint32) raw[p] | ((uint32) raw[p + 1] << 8) | ((uint32) raw[p + 2] << 16) | ((uint32) raw[p + 3] << 24);
                                v = (float) u;
                                p += 4;
                            }
                            size_t o = img.offset (x, y + ly);
                            if (ch == 4) {
                                img.data[o] = img.data[o + 1] = img.data[o + 2] = v;
                            } else if (ch >= 0) {
                                img.data[o + ch] = v;
                            }
                        }
                    }
                }
            }
            if (has_alpha) Pixels.unpremultiply (img);
            return img;
        }

        private uint8[] unrle (uint8[] src, size_t expected) {
            var out_data = new ByteArray.sized ((uint) expected);
            size_t i = 0;
            while (i < src.length) {
                int8 n = (int8) src[i++];
                if (n < 0) {
                    int count = -n;
                    out_data.append (src[i:i + count]);
                    i += count;
                } else {
                    var rep = new uint8[n + 1];
                    for (int k = 0; k <= n; k++) rep[k] = src[i];
                    out_data.append (rep);
                    i++;
                }
            }
            return unpredict (out_data.steal ());
        }

        private uint8[] unpredict (uint8[] t) {
            for (int i = 1; i < t.length; i++) t[i] = (uint8) ((t[i - 1] + t[i] - 128) & 0xff);
            var out_data = new uint8[t.length];
            int half = (t.length + 1) / 2;
            for (int i = 0; i < t.length; i++) out_data[i] = (i % 2 == 0) ? t[i / 2] : t[half + i / 2];
            return out_data;
        }

        private uint8[] predict (uint8[] raw) {
            var t = new uint8[raw.length];
            int half = (raw.length + 1) / 2;
            for (int i = 0; i < raw.length; i++) {
                if (i % 2 == 0) t[i / 2] = raw[i];
                else t[half + i / 2] = raw[i];
            }
            int prev = t.length > 0 ? t[0] : 0;
            for (int i = 1; i < t.length; i++) {
                int d = t[i] - prev + 128 + 256;
                prev = t[i];
                t[i] = (uint8) (d & 0xff);
            }
            return t;
        }

        private void put32 (ByteArray b, uint32 v) {
            uint8[] x = { (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) };
            b.append (x);
        }

        private void attr (ByteArray b, string name, string type, uint8[] value) {
            b.append (name.data);
            b.append ({ 0 });
            b.append (type.data);
            b.append ({ 0 });
            put32 (b, value.length);
            b.append (value);
        }

        public uint8[] encode (FloatImage premul, bool half, bool zip, bool alpha = true) throws Error {
            int w = premul.width, h = premul.height;
            string[] names = alpha ? new string[] { "A", "B", "G", "R" } : new string[] { "B", "G", "R" };
            int[] idx = alpha ? new int[] { 3, 2, 1, 0 } : new int[] { 2, 1, 0 };
            var b = new ByteArray ();
            put32 (b, 20000630);
            put32 (b, 2);
            var ch = new ByteArray ();
            foreach (var n in names) {
                ch.append (n.data);
                ch.append ({ 0 });
                put32 (ch, half ? 1 : 2);
                put32 (ch, 0);
                put32 (ch, 1);
                put32 (ch, 1);
            }
            ch.append ({ 0 });
            attr (b, "channels", "chlist", ch.data);
            attr (b, "compression", "compression", { (uint8) (zip ? 3 : 0) });
            var box = new ByteArray ();
            put32 (box, 0);
            put32 (box, 0);
            put32 (box, w - 1);
            put32 (box, h - 1);
            attr (b, "dataWindow", "box2i", box.data);
            attr (b, "displayWindow", "box2i", box.data);
            attr (b, "lineOrder", "lineOrder", { 0 });
            var par = new ByteArray ();
            float one = 1;
            put32 (par, *((uint32*) (&one)));
            attr (b, "pixelAspectRatio", "float", par.data);
            var swc = new ByteArray ();
            put32 (swc, 0);
            put32 (swc, 0);
            attr (b, "screenWindowCenter", "v2f", swc.data);
            attr (b, "screenWindowWidth", "float", par.data);
            b.append ({ 0 });
            int lines = zip ? 16 : 1;
            int blocks = (h + lines - 1) / lines;
            size_t table_pos = b.len;
            for (int i = 0; i < blocks * 2; i++) put32 (b, 0);
            var offsets = new uint64[blocks];
            int bps = half ? 2 : 4;
            for (int blk = 0; blk < blocks; blk++) {
                int y0 = blk * lines;
                int n = int.min (lines, h - y0);
                var raw = new uint8[(size_t) n * w * names.length * bps];
                size_t p = 0;
                for (int ly = 0; ly < n; ly++)
                    for (int c = 0; c < names.length; c++)
                        for (int x = 0; x < w; x++) {
                            float v = premul.data[premul.offset (x, y0 + ly) + idx[c]];
                            if (half) {
                                uint16 hv = Half.from_float (v);
                                raw[p++] = (uint8) hv;
                                raw[p++] = (uint8) (hv >> 8);
                            } else {
                                uint32 bits = *((uint32*) (&v));
                                raw[p++] = (uint8) bits;
                                raw[p++] = (uint8) (bits >> 8);
                                raw[p++] = (uint8) (bits >> 16);
                                raw[p++] = (uint8) (bits >> 24);
                            }
                        }
                uint8[] payload = raw;
                if (zip) {
                    var z = ImageIO.deflate_zlib (predict (raw));
                    if (z.length < raw.length) payload = z;
                }
                offsets[blk] = b.len;
                put32 (b, y0);
                put32 (b, payload.length);
                b.append (payload);
            }
            for (int i = 0; i < blocks; i++) {
                size_t o = table_pos + i * 8;
                uint64 v = offsets[i];
                for (int k = 0; k < 8; k++) b.data[o + k] = (uint8) (v >> (8 * k));
            }
            return b.steal ();
        }
    }
}
