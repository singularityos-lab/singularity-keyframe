using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace Gif {
        private class Box {
            public int[] idx;
            public int lo;
            public int hi;
        }

        public uint8[] median_cut (uint8[] samples, int count, int colors) {
            var all = new int[count];
            for (int i = 0; i < count; i++) all[i] = i;
            var boxes = new Gee.ArrayList<Box> ();
            var first = new Box ();
            first.idx = all;
            boxes.add (first);
            while (boxes.size < colors) {
                Box? best = null;
                int best_range = -1, best_ch = 0;
                foreach (var b in boxes) {
                    if (b.idx.length < 2) continue;
                    for (int c = 0; c < 3; c++) {
                        int mn = 255, mx = 0;
                        foreach (var i in b.idx) {
                            int v = samples[i * 3 + c];
                            if (v < mn) mn = v;
                            if (v > mx) mx = v;
                        }
                        int range = (mx - mn) * b.idx.length.clamp (1, 1000000) / 64 + (mx - mn);
                        if (mx - mn > 0 && range > best_range) {
                            best_range = range;
                            best = b;
                            best_ch = c;
                        }
                    }
                }
                if (best == null) break;
                int ch = best_ch;
                var sorted = best.idx;
                var hist = new int[256];
                foreach (var i in sorted) hist[samples[i * 3 + ch]]++;
                int half = sorted.length / 2, acc = 0, split = 0;
                for (int v = 0; v < 256; v++) {
                    acc += hist[v];
                    if (acc >= half) {
                        split = v;
                        break;
                    }
                }
                int[] a = {}, b2 = {};
                foreach (var i in sorted) {
                    if (samples[i * 3 + ch] <= split) a += i;
                    else b2 += i;
                }
                if (a.length == 0 || b2.length == 0) {
                    a = sorted[0:half];
                    b2 = sorted[half:sorted.length];
                }
                boxes.remove (best);
                var ba = new Box ();
                ba.idx = a;
                var bb = new Box ();
                bb.idx = b2;
                boxes.add (ba);
                boxes.add (bb);
            }
            var pal = new uint8[colors * 3];
            for (int k = 0; k < boxes.size; k++) {
                long r = 0, g = 0, b = 0;
                foreach (var i in boxes[k].idx) {
                    r += samples[i * 3];
                    g += samples[i * 3 + 1];
                    b += samples[i * 3 + 2];
                }
                int n = int.max (1, boxes[k].idx.length);
                pal[k * 3] = (uint8) (r / n);
                pal[k * 3 + 1] = (uint8) (g / n);
                pal[k * 3 + 2] = (uint8) (b / n);
            }
            return pal;
        }

        private int nearest (uint8[] pal, int ncolors, int r, int g, int b) {
            int best = 0, bd = int.MAX;
            for (int i = 0; i < ncolors; i++) {
                int dr = pal[i * 3] - r, dg = pal[i * 3 + 1] - g, db = pal[i * 3 + 2] - b;
                int d = dr * dr * 3 + dg * dg * 4 + db * db * 2;
                if (d < bd) {
                    bd = d;
                    best = i;
                }
            }
            return best;
        }

        private class BitWriter {
            public ByteArray out_data = new ByteArray ();
            private uint32 acc = 0;
            private int nbits = 0;

            public void write (int code, int size) {
                acc |= (uint32) code << nbits;
                nbits += size;
                while (nbits >= 8) {
                    out_data.append ({ (uint8) (acc & 0xff) });
                    acc >>= 8;
                    nbits -= 8;
                }
            }

            public void flush () {
                if (nbits > 0) out_data.append ({ (uint8) (acc & 0xff) });
                acc = 0;
                nbits = 0;
            }
        }

        public uint8[] lzw (uint8[] indices, int min_size) {
            int clear = 1 << min_size, eoi = clear + 1;
            var w = new BitWriter ();
            int size = min_size + 1;
            var dict = new Gee.HashMap<int, int> ();
            int next = eoi + 1;
            w.write (clear, size);
            if (indices.length == 0) {
                w.write (eoi, size);
                w.flush ();
                return w.out_data.steal ();
            }
            int prefix = indices[0];
            for (int i = 1; i < indices.length; i++) {
                int k = indices[i];
                int key = (prefix << 8) | k;
                if (dict.has_key (key)) {
                    prefix = dict[key];
                    continue;
                }
                w.write (prefix, size);
                if (next < 4096) {
                    dict[key] = next++;
                    if (next > (1 << size) && size < 12) size++;
                } else {
                    w.write (clear, size);
                    dict.clear ();
                    next = eoi + 1;
                    size = min_size + 1;
                }
                prefix = k;
            }
            w.write (prefix, size);
            w.write (eoi, size);
            w.flush ();
            return w.out_data.steal ();
        }

        private void put16 (ByteArray b, int v) {
            b.append ({ (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) });
        }

        public uint8[] encode (Gee.List<Bytes> frames, int w, int h, double fps, bool dither, bool loop = true) {
            bool any_alpha = false;
            int total = frames.size * w * h;
            int stride = int.max (1, total / 400000);
            var samples = new ByteArray ();
            int count = 0;
            int pos = 0;
            foreach (var f in frames) {
                unowned uint8[] px = f.get_data ();
                for (int i = 0; i < w * h; i++, pos++) {
                    if (px[i * 4 + 3] < 128) {
                        any_alpha = true;
                        continue;
                    }
                    if (pos % stride != 0) continue;
                    samples.append ({ px[i * 4], px[i * 4 + 1], px[i * 4 + 2] });
                    count++;
                }
            }
            int ncolors = any_alpha ? 255 : 256;
            var pal = count > 0 ? median_cut (samples.data, count, ncolors) : new uint8[ncolors * 3];
            int transparent = any_alpha ? 255 : -1;
            var b = new ByteArray ();
            b.append ("GIF89a".data);
            put16 (b, w);
            put16 (b, h);
            b.append ({ 0xF7, 0, 0 });
            var full = new uint8[768];
            for (int i = 0; i < pal.length && i < 768; i++) full[i] = pal[i];
            b.append (full);
            if (loop) {
                b.append ({ 0x21, 0xFF, 0x0B });
                b.append ("NETSCAPE2.0".data);
                b.append ({ 3, 1, 0, 0, 0 });
            }
            var cache = new Gee.HashMap<int, int> ();
            for (int fi = 0; fi < frames.size; fi++) {
                unowned uint8[] px = frames[fi].get_data ();
                var err = new float[w * h * 3];
                var idx = new uint8[w * h];
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++) {
                        int i = y * w + x;
                        if (transparent >= 0 && px[i * 4 + 3] < 128) {
                            idx[i] = (uint8) transparent;
                            continue;
                        }
                        int r = ((int) Math.roundf (px[i * 4] + err[i * 3])).clamp (0, 255);
                        int g = ((int) Math.roundf (px[i * 4 + 1] + err[i * 3 + 1])).clamp (0, 255);
                        int bl = ((int) Math.roundf (px[i * 4 + 2] + err[i * 3 + 2])).clamp (0, 255);
                        int key = ((r >> 2) << 12) | ((g >> 2) << 6) | (bl >> 2);
                        int ci;
                        if (cache.has_key (key)) ci = cache[key];
                        else {
                            ci = nearest (pal, ncolors, r, g, bl);
                            cache[key] = ci;
                        }
                        idx[i] = (uint8) ci;
                        if (dither) {
                            float er = r - pal[ci * 3], eg = g - pal[ci * 3 + 1], eb = bl - pal[ci * 3 + 2];
                            spread (err, w, h, x + 1, y, er, eg, eb, 7.0f / 16);
                            spread (err, w, h, x - 1, y + 1, er, eg, eb, 3.0f / 16);
                            spread (err, w, h, x, y + 1, er, eg, eb, 5.0f / 16);
                            spread (err, w, h, x + 1, y + 1, er, eg, eb, 1.0f / 16);
                        }
                    }
                int delay = (int) (Math.round ((fi + 1) * 100.0 / fps) - Math.round (fi * 100.0 / fps));
                b.append ({ 0x21, 0xF9, 4, (uint8) (transparent >= 0 ? 0x09 : 0x04) });
                put16 (b, delay);
                b.append ({ (uint8) (transparent >= 0 ? transparent : 0), 0 });
                b.append ({ 0x2C });
                put16 (b, 0);
                put16 (b, 0);
                put16 (b, w);
                put16 (b, h);
                b.append ({ 0, 8 });
                var data = lzw (idx, 8);
                for (int p = 0; p < data.length; p += 255) {
                    int n = int.min (255, data.length - p);
                    b.append ({ (uint8) n });
                    b.append (data[p:p + n]);
                }
                b.append ({ 0 });
            }
            b.append ({ 0x3B });
            return b.steal ();
        }

        private void spread (float[] err, int w, int h, int x, int y, float er, float eg, float eb, float k) {
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            int i = (y * w + x) * 3;
            err[i] += er * k;
            err[i + 1] += eg * k;
            err[i + 2] += eb * k;
        }
    }

    public class GifSink : FrameSink {
        private Gee.ArrayList<Bytes> frames = new Gee.ArrayList<Bytes> ();

        public override void begin (int width, int height, double fps) throws Error {
            this.width = width;
            this.height = height;
            this.fps = fps;
            DirUtils.create_with_parents (Path.get_dirname (path), 0755);
        }

        public override void write (FloatImage premul, int index) throws Error {
            frames.add (new Bytes.take (Encoders.rgba8 (premul, module.alpha)));
        }

        public override void finish () throws Error {
            FileUtils.set_data (path, Gif.encode (frames, width, height, fps, module.quality >= 50));
            written.add (path);
        }
    }
}
