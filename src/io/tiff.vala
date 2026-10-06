using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace Tiff {
        public bool last_was_float = false;

        private class In {
            public unowned uint8[] d;
            public bool le = true;

            public In (uint8[] d) {
                this.d = d;
            }

            public uint16 u16 (size_t p) throws Error {
                if (p + 2 > d.length) throw new ImageError.FORMAT ("Truncated TIFF");
                return le ? (uint16) (d[p] | (d[p + 1] << 8)) : (uint16) ((d[p] << 8) | d[p + 1]);
            }

            public uint32 u32 (size_t p) throws Error {
                if (p + 4 > d.length) throw new ImageError.FORMAT ("Truncated TIFF");
                if (le) return (uint32) d[p] | ((uint32) d[p + 1] << 8) | ((uint32) d[p + 2] << 16) | ((uint32) d[p + 3] << 24);
                return ((uint32) d[p] << 24) | ((uint32) d[p + 1] << 16) | ((uint32) d[p + 2] << 8) | (uint32) d[p + 3];
            }

            public uint32[] values (size_t entry) throws Error {
                uint16 type = u16 (entry + 2);
                uint32 count = u32 (entry + 4);
                int size = type == 3 ? 2 : 4;
                size_t p = count * size <= 4 ? entry + 8 : u32 (entry + 8);
                var r = new uint32[count];
                for (uint32 i = 0; i < count; i++) r[i] = type == 3 ? u16 (p + i * 2) : u32 (p + i * 4);
                return r;
            }
        }

        public FloatImage decode (uint8[] data) throws Error {
            var r = new In (data);
            if (data.length < 8) throw new ImageError.FORMAT ("Not a TIFF file");
            if (data[0] == 'M' && data[1] == 'M') r.le = false;
            else if (!(data[0] == 'I' && data[1] == 'I')) throw new ImageError.FORMAT ("Not a TIFF file");
            if (r.u16 (2) != 42) throw new ImageError.UNSUPPORTED ("BigTIFF is not supported");
            size_t ifd = r.u32 (4);
            int n = r.u16 (ifd);
            uint32 width = 0, height = 0, compression = 1, photometric = 2, spp = 1, rows_per_strip = 0, predictor = 1, planar = 1;
            uint32[] bps = { 8 };
            uint32[] offsets = {};
            uint32[] counts = {};
            uint32 sample_format = 1;
            uint32 extra = 0;
            for (int i = 0; i < n; i++) {
                size_t e = ifd + 2 + i * 12;
                uint16 tag = r.u16 (e);
                var v = r.values (e);
                if (v.length == 0) continue;
                switch (tag) {
                    case 256: width = v[0]; break;
                    case 257: height = v[0]; break;
                    case 258: bps = v; break;
                    case 259: compression = v[0]; break;
                    case 262: photometric = v[0]; break;
                    case 273: offsets = v; break;
                    case 277: spp = v[0]; break;
                    case 278: rows_per_strip = v[0]; break;
                    case 279: counts = v; break;
                    case 284: planar = v[0]; break;
                    case 317: predictor = v[0]; break;
                    case 338: extra = v[0]; break;
                    case 339: sample_format = v[0]; break;
                }
            }
            if (width == 0 || height == 0 || offsets.length == 0) throw new ImageError.FORMAT ("Bad TIFF");
            if (planar != 1) throw new ImageError.UNSUPPORTED ("Planar TIFF is not supported");
            int bits = (int) bps[0];
            int bytes = bits / 8;
            if (bits != 8 && bits != 16 && bits != 32) throw new ImageError.UNSUPPORTED ("TIFF bit depth %d is not supported", bits);
            if (rows_per_strip == 0) rows_per_strip = height;
            size_t row_bytes = (size_t) width * spp * bytes;
            var pixels = new ByteArray ();
            for (int s = 0; s < offsets.length; s++) {
                uint8[] chunk = data[offsets[s]:offsets[s] + counts[s]];
                uint8[] raw;
                switch (compression) {
                    case 1: raw = chunk; break;
                    case 8:
                    case 32946: raw = ImageIO.inflate_zlib (chunk); break;
                    case 32773: raw = unpackbits (chunk); break;
                    case 5: raw = unlzw (chunk); break;
                    default: throw new ImageError.UNSUPPORTED ("TIFF compression %u is not supported", compression);
                }
                pixels.append (raw);
            }
            var px = pixels.data;
            if (px.length < row_bytes * height) throw new ImageError.FORMAT ("Truncated TIFF data");
            if (predictor == 2) {
                for (uint32 y = 0; y < height; y++) {
                    size_t row = y * row_bytes;
                    for (size_t x = spp; x < (size_t) width * spp; x++) {
                        if (bytes == 1) px[row + x] = (uint8) (px[row + x] + px[row + x - spp]);
                        else if (bytes == 2) {
                            size_t a = row + x * 2, b = row + (x - spp) * 2;
                            uint16 va = r.le ? (uint16) (px[a] | (px[a + 1] << 8)) : (uint16) ((px[a] << 8) | px[a + 1]);
                            uint16 vb = r.le ? (uint16) (px[b] | (px[b + 1] << 8)) : (uint16) ((px[b] << 8) | px[b + 1]);
                            uint16 s = (uint16) (va + vb);
                            if (r.le) {
                                px[a] = (uint8) s;
                                px[a + 1] = (uint8) (s >> 8);
                            } else {
                                px[a] = (uint8) (s >> 8);
                                px[a + 1] = (uint8) s;
                            }
                        }
                    }
                }
            }
            var img = new FloatImage ((int) width, (int) height);
            last_was_float = sample_format == 3;
            for (uint32 y = 0; y < height; y++)
                for (uint32 x = 0; x < width; x++) {
                    size_t base_pos = y * row_bytes + (size_t) x * spp * bytes;
                    float[] c = new float[4];
                    for (int k = 0; k < (int) spp && k < 4; k++) {
                        size_t p = base_pos + k * bytes;
                        float v;
                        if (bytes == 1) v = px[p] / 255.0f;
                        else if (bytes == 2) v = (r.le ? (px[p] | (px[p + 1] << 8)) : ((px[p] << 8) | px[p + 1])) / 65535.0f;
                        else {
                            uint32 u = r.le ? ((uint32) px[p] | ((uint32) px[p + 1] << 8) | ((uint32) px[p + 2] << 16) | ((uint32) px[p + 3] << 24))
                                            : (((uint32) px[p] << 24) | ((uint32) px[p + 1] << 16) | ((uint32) px[p + 2] << 8) | (uint32) px[p + 3]);
                            v = sample_format == 3 ? *((float*) (&u)) : (float) (u / 4294967295.0);
                        }
                        c[k] = v;
                    }
                    size_t o = img.offset ((int) x, (int) y);
                    if (spp < 3) {
                        float g = photometric == 0 ? 1 - c[0] : c[0];
                        img.data[o] = img.data[o + 1] = img.data[o + 2] = g;
                        img.data[o + 3] = spp == 2 ? c[1] : 1;
                    } else {
                        img.data[o] = c[0];
                        img.data[o + 1] = c[1];
                        img.data[o + 2] = c[2];
                        img.data[o + 3] = spp >= 4 ? c[3] : 1;
                    }
                }
            if (extra == 1 && spp >= 4) Pixels.unpremultiply (img);
            return img;
        }

        private uint8[] unpackbits (uint8[] src) {
            var out_data = new ByteArray ();
            size_t i = 0;
            while (i < src.length) {
                int8 n = (int8) src[i++];
                if (n >= 0) {
                    out_data.append (src[i:i + n + 1]);
                    i += n + 1;
                } else if (n != -128) {
                    var rep = new uint8[1 - n];
                    for (int k = 0; k < rep.length; k++) rep[k] = src[i];
                    out_data.append (rep);
                    i++;
                }
            }
            return out_data.steal ();
        }

        private uint8[] unlzw (uint8[] src) {
            var out_data = new ByteArray ();
            var table = new Gee.ArrayList<Bytes> ();
            int bitpos = 0;
            int code_len = 9;
            Bytes? prev = null;
            for (int i = 0; i < 256; i++) table.add (new Bytes ({ (uint8) i }));
            table.add (new Bytes ({}));
            table.add (new Bytes ({}));
            while (true) {
                if ((bitpos + code_len) / 8 >= src.length + 1) break;
                int code = 0;
                for (int k = 0; k < code_len; k++) {
                    int byte_index = (bitpos + k) / 8;
                    int bit = byte_index < src.length ? (src[byte_index] >> (7 - (bitpos + k) % 8)) & 1 : 0;
                    code = (code << 1) | bit;
                }
                bitpos += code_len;
                if (code == 257) break;
                if (code == 256) {
                    while (table.size > 258) table.remove_at (table.size - 1);
                    code_len = 9;
                    prev = null;
                    continue;
                }
                Bytes entry;
                if (code < table.size) {
                    entry = table[code];
                    if (prev != null) {
                        var nb = new ByteArray ();
                        nb.append (prev.get_data ());
                        nb.append ({ entry.get_data ()[0] });
                        table.add (ByteArray.free_to_bytes (nb));
                    }
                } else if (prev != null) {
                    var nb = new ByteArray ();
                    nb.append (prev.get_data ());
                    nb.append ({ prev.get_data ()[0] });
                    entry = ByteArray.free_to_bytes (nb);
                    table.add (entry);
                } else {
                    break;
                }
                out_data.append (entry.get_data ());
                prev = entry;
                if (table.size >= 511 && code_len == 9) code_len = 10;
                else if (table.size >= 1023 && code_len == 10) code_len = 11;
                else if (table.size >= 2047 && code_len == 11) code_len = 12;
            }
            return out_data.steal ();
        }

        private void p16 (ByteArray b, uint v) {
            b.append ({ (uint8) v, (uint8) (v >> 8) });
        }

        private void p32 (ByteArray b, uint32 v) {
            b.append ({ (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) });
        }

        public uint8[] encode (FloatImage premul, int bit_depth, bool alpha, bool deflate) throws Error {
            var img = Pixels.unpremultiplied (premul);
            int w = img.width, h = img.height;
            int spp = alpha ? 4 : 3;
            int bytes = bit_depth >= 32 ? 4 : (bit_depth >= 16 ? 2 : 1);
            var raw = new uint8[(size_t) w * h * spp * bytes];
            size_t p = 0;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    size_t i = img.offset (x, y);
                    for (int c = 0; c < spp; c++) {
                        float v = img.data[i + c];
                        if (bytes == 4) {
                            uint32 u = *((uint32*) (&v));
                            raw[p++] = (uint8) u;
                            raw[p++] = (uint8) (u >> 8);
                            raw[p++] = (uint8) (u >> 16);
                            raw[p++] = (uint8) (u >> 24);
                            continue;
                        }
                        if (c < 3) v = Transfer.linear_to_srgb (v.clamp (0, 1));
                        v = v.clamp (0, 1);
                        if (bytes == 2) {
                            uint16 s = (uint16) Math.roundf (v * 65535);
                            raw[p++] = (uint8) s;
                            raw[p++] = (uint8) (s >> 8);
                        } else {
                            raw[p++] = (uint8) Math.roundf (v * 255);
                        }
                    }
                }
            uint8[] payload = deflate ? ImageIO.deflate_zlib (raw) : raw;
            var b = new ByteArray ();
            b.append ({ 'I', 'I' });
            p16 (b, 42);
            p32 (b, 8);
            int entries = alpha ? 12 : 11;
            uint32 ifd_size = 2 + entries * 12 + 4;
            uint32 bps_pos = 8 + ifd_size;
            uint32 data_pos = bps_pos + spp * 2;
            p16 (b, entries);
            tag (b, 256, 4, 1, w);
            tag (b, 257, 4, 1, h);
            tag (b, 258, 3, spp, bps_pos);
            tag (b, 259, 3, 1, deflate ? 8 : 1);
            tag (b, 262, 3, 1, 2);
            tag (b, 273, 4, 1, data_pos);
            tag (b, 277, 3, 1, spp);
            tag (b, 278, 4, 1, h);
            tag (b, 279, 4, 1, payload.length);
            tag (b, 284, 3, 1, 1);
            if (alpha) tag (b, 338, 3, 1, 2);
            tag (b, 339, 3, 1, bytes == 4 ? 3 : 1);
            p32 (b, 0);
            for (int i = 0; i < spp; i++) p16 (b, bytes * 8);
            b.append (payload);
            return b.steal ();
        }

        private void tag (ByteArray b, uint16 id, uint16 type, uint32 count, uint32 value) {
            p16 (b, id);
            p16 (b, type);
            p32 (b, count);
            if (type == 3 && count == 1) {
                p16 (b, value);
                p16 (b, 0);
            } else {
                p32 (b, value);
            }
        }
    }
}
