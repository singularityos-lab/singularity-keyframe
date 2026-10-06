using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class LayerBuffer {
        public FloatImage img;
        public double x0;
        public double y0;
        public double scale;

        public LayerBuffer (FloatImage img, double x0, double y0, double scale) {
            this.img = img;
            this.x0 = x0;
            this.y0 = y0;
            this.scale = scale;
        }

        public LayerBuffer copy () {
            return new LayerBuffer (img.copy (), x0, y0, scale);
        }

        public double width_units () {
            return img.width / scale;
        }

        public double height_units () {
            return img.height / scale;
        }

        public void to_pixel (double lx, double ly, out double px, out double py) {
            px = (lx - x0) * scale;
            py = (ly - y0) * scale;
        }

        public void to_layer (double px, double py, out double lx, out double ly) {
            lx = px / scale + x0;
            ly = py / scale + y0;
        }

        public LayerBuffer padded (double units) {
            int pad = (int) Math.ceil (units * scale);
            if (pad <= 0) return this;
            pad = int.min (pad, 4096);
            var n = new FloatImage (img.width + pad * 2, img.height + pad * 2);
            for (int y = 0; y < img.height; y++)
                Memory.copy (&n.data[n.offset (pad, y + pad)], &img.data[img.offset (0, y)], (size_t) img.width * 4 * sizeof (float));
            return new LayerBuffer (n, x0 - pad / scale, y0 - pad / scale, scale);
        }

        public Mat4 pixel_to_layer () {
            return Mat4.translation (x0, y0, 0).multiply (Mat4.scaling (1.0 / scale, 1.0 / scale, 1));
        }
    }

    public class CompImage {
        public FloatImage img;
        public int x;
        public int y;

        public CompImage (FloatImage img, int x, int y) {
            this.img = img;
            this.x = x;
            this.y = y;
        }

        public bool empty () {
            return img.width <= 1 && img.height <= 1 && img.data[3] == 0;
        }

        public void get_pixel_at (int cx, int cy, out float r, out float g, out float b, out float a) {
            int px = cx - x, py = cy - y;
            if (px < 0 || py < 0 || px >= img.width || py >= img.height) {
                r = g = b = a = 0;
                return;
            }
            size_t i = img.offset (px, py);
            r = img.data[i];
            g = img.data[i + 1];
            b = img.data[i + 2];
            a = img.data[i + 3];
        }
    }

    namespace Pixels {
        public void premultiply (FloatImage img) {
            Parallel.range (img.height, (s, e) => {
                for (size_t i = (size_t) s * img.width; i < (size_t) e * img.width; i++) {
                    float a = img.data[i * 4 + 3];
                    img.data[i * 4] *= a;
                    img.data[i * 4 + 1] *= a;
                    img.data[i * 4 + 2] *= a;
                }
            });
        }

        public void unpremultiply (FloatImage img) {
            Parallel.range (img.height, (s, e) => {
                for (size_t i = (size_t) s * img.width; i < (size_t) e * img.width; i++) {
                    float a = img.data[i * 4 + 3];
                    if (a > 1e-6f) {
                        img.data[i * 4] /= a;
                        img.data[i * 4 + 1] /= a;
                        img.data[i * 4 + 2] /= a;
                    } else {
                        img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = 0;
                    }
                }
            });
        }

        public FloatImage unpremultiplied (FloatImage img) {
            var c = img.copy ();
            unpremultiply (c);
            return c;
        }

        public void scale_alpha (FloatImage img, float f) {
            if (f >= 0.9999f) return;
            size_t n = img.pixel_count () * 4;
            for (size_t i = 0; i < n; i++) img.data[i] *= f;
        }

        public void multiply_mask (FloatImage img, float[] mask) {
            Parallel.range (img.height, (s, e) => {
                for (size_t i = (size_t) s * img.width; i < (size_t) e * img.width; i++) {
                    float m = mask[i];
                    img.data[i * 4] *= m;
                    img.data[i * 4 + 1] *= m;
                    img.data[i * 4 + 2] *= m;
                    img.data[i * 4 + 3] *= m;
                }
            });
        }

        public void sample_premul (FloatImage img, double x, double y, out float r, out float g, out float b, out float a) {
            double fx = x - 0.5, fy = y - 0.5;
            int x0 = (int) Math.floor (fx), y0 = (int) Math.floor (fy);
            float tx = (float) (fx - x0), ty = (float) (fy - y0);
            r = g = b = a = 0;
            for (int j = 0; j < 2; j++) {
                int yy = y0 + j;
                if (yy < 0 || yy >= img.height) continue;
                float wy = j == 0 ? 1 - ty : ty;
                for (int i = 0; i < 2; i++) {
                    int xx = x0 + i;
                    if (xx < 0 || xx >= img.width) continue;
                    float w = wy * (i == 0 ? 1 - tx : tx);
                    if (w <= 0) continue;
                    size_t o = img.offset (xx, yy);
                    r += img.data[o] * w;
                    g += img.data[o + 1] * w;
                    b += img.data[o + 2] * w;
                    a += img.data[o + 3] * w;
                }
            }
        }

        public FloatImage box_downsample (FloatImage src, int factor) {
            if (factor <= 1) return src;
            int w = int.max (1, src.width / factor), h = int.max (1, src.height / factor);
            var dst = new FloatImage (w, h);
            float inv = 1.0f / (factor * factor);
            Parallel.range (h, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < w; x++) {
                        float r = 0, g = 0, b = 0, a = 0;
                        for (int yy = 0; yy < factor; yy++)
                            for (int xx = 0; xx < factor; xx++) {
                                size_t o = src.offset (int.min (x * factor + xx, src.width - 1), int.min (y * factor + yy, src.height - 1));
                                r += src.data[o];
                                g += src.data[o + 1];
                                b += src.data[o + 2];
                                a += src.data[o + 3];
                            }
                        size_t d = dst.offset (x, y);
                        dst.data[d] = r * inv;
                        dst.data[d + 1] = g * inv;
                        dst.data[d + 2] = b * inv;
                        dst.data[d + 3] = a * inv;
                    }
            });
            return dst;
        }

        public float luma (float r, float g, float b) {
            return 0.2126f * r + 0.7152f * g + 0.0722f * b;
        }

        private float dissolve_noise (int x, int y) {
            uint h = (uint) x * 374761393u + (uint) y * 668265263u;
            h = (h ^ (h >> 13)) * 1274126177u;
            return (h ^ (h >> 16)) / 4294967295.0f;
        }

        public void blend (FloatImage dst, CompImage src, BlendMode mode, bool linear, bool preserve_transparency) {
            int x0 = int.max (0, src.x), y0 = int.max (0, src.y);
            int x1 = int.min (dst.width, src.x + src.img.width), y1 = int.min (dst.height, src.y + src.img.height);
            if (x0 >= x1 || y0 >= y1) return;
            Parallel.range (y1 - y0, (s, e) => {
                for (int y = y0 + s; y < y0 + e; y++) {
                    for (int x = x0; x < x1; x++) {
                        size_t si = src.img.offset (x - src.x, y - src.y);
                        size_t di = dst.offset (x, y);
                        float sa = src.img.data[si + 3];
                        if (sa <= 0) continue;
                        float sr = src.img.data[si], sg = src.img.data[si + 1], sb = src.img.data[si + 2];
                        float ba = dst.data[di + 3];
                        if (preserve_transparency) {
                            sr *= ba;
                            sg *= ba;
                            sb *= ba;
                            sa *= ba;
                            if (sa <= 0) continue;
                        }
                        if (mode == BlendMode.NORMAL) {
                            float k = 1 - sa;
                            dst.data[di] = sr + dst.data[di] * k;
                            dst.data[di + 1] = sg + dst.data[di + 1] * k;
                            dst.data[di + 2] = sb + dst.data[di + 2] * k;
                            dst.data[di + 3] = sa + ba * k;
                            continue;
                        }
                        if (mode == BlendMode.DISSOLVE) {
                            float keep = dissolve_noise (x, y) < sa ? 1 : 0;
                            if (keep == 0) continue;
                            dst.data[di] = sr / sa;
                            dst.data[di + 1] = sg / sa;
                            dst.data[di + 2] = sb / sa;
                            dst.data[di + 3] = 1;
                            continue;
                        }
                        float cs_r = sr / sa, cs_g = sg / sa, cs_b = sb / sa;
                        float cb_r = 0, cb_g = 0, cb_b = 0;
                        if (ba > 1e-6f) {
                            cb_r = dst.data[di] / ba;
                            cb_g = dst.data[di + 1] / ba;
                            cb_b = dst.data[di + 2] / ba;
                        }
                        if (mode == BlendMode.LINEAR_DODGE && linear) {
                            float k = 1 - sa;
                            dst.data[di] = sr + dst.data[di] * (ba > 0 ? 1 : k);
                            dst.data[di + 1] = sg + dst.data[di + 1] * (ba > 0 ? 1 : k);
                            dst.data[di + 2] = sb + dst.data[di + 2] * (ba > 0 ? 1 : k);
                            dst.data[di + 3] = sa + ba * k;
                            continue;
                        }
                        float pr = cs_r, pg = cs_g, pb = cs_b, qr = cb_r, qg = cb_g, qb = cb_b;
                        if (!linear) {
                            pr = Transfer.linear_to_srgb (pr.clamp (0, 1));
                            pg = Transfer.linear_to_srgb (pg.clamp (0, 1));
                            pb = Transfer.linear_to_srgb (pb.clamp (0, 1));
                            qr = Transfer.linear_to_srgb (qr.clamp (0, 1));
                            qg = Transfer.linear_to_srgb (qg.clamp (0, 1));
                            qb = Transfer.linear_to_srgb (qb.clamp (0, 1));
                        }
                        float mr, mg, mb;
                        Singularity.Imaging.Blend.mix (mode, qr.clamp (0, 1), qg.clamp (0, 1), qb.clamp (0, 1), pr.clamp (0, 1), pg.clamp (0, 1), pb.clamp (0, 1), out mr, out mg, out mb);
                        if (!linear) {
                            mr = Transfer.srgb_to_linear (mr);
                            mg = Transfer.srgb_to_linear (mg);
                            mb = Transfer.srgb_to_linear (mb);
                        }
                        float oa = sa + ba - sa * ba;
                        dst.data[di] = (1 - ba) * sr + (1 - sa) * dst.data[di] + sa * ba * mr;
                        dst.data[di + 1] = (1 - ba) * sg + (1 - sa) * dst.data[di + 1] + sa * ba * mg;
                        dst.data[di + 2] = (1 - ba) * sb + (1 - sa) * dst.data[di + 2] + sa * ba * mb;
                        dst.data[di + 3] = oa;
                    }
                }
            });
        }

        public void quantize (FloatImage img, int bit_depth) {
            if (bit_depth >= 32) return;
            float levels = bit_depth <= 8 ? 255.0f : 32768.0f;
            Parallel.range (img.height, (s, e) => {
                for (size_t i = (size_t) s * img.width; i < (size_t) e * img.width; i++) {
                    float a = img.data[i * 4 + 3].clamp (0, 1);
                    a = Math.roundf (a * levels) / levels;
                    for (int c = 0; c < 3; c++) {
                        float v = img.data[i * 4 + c].clamp (0, 1);
                        if (bit_depth <= 8) {
                            float enc = Transfer.linear_to_srgb (v);
                            enc = Math.roundf (enc * 255.0f) / 255.0f;
                            v = Transfer.srgb_to_linear (enc);
                        } else {
                            v = Math.roundf (v * levels) / levels;
                        }
                        img.data[i * 4 + c] = float.min (v, a);
                    }
                    img.data[i * 4 + 3] = a;
                }
            });
        }

        public void mix_into (FloatImage dst, FloatImage src, float t) {
            size_t n = dst.pixel_count () * 4;
            for (size_t i = 0; i < n; i++) dst.data[i] += (src.data[i] - dst.data[i]) * t;
        }

        public void accumulate (FloatImage dst, FloatImage src, float w) {
            size_t n = dst.pixel_count () * 4;
            for (size_t i = 0; i < n; i++) dst.data[i] += src.data[i] * w;
        }

        public FloatImage convert_space (FloatImage premul, string from, string to) {
            if (from == to) return premul;
            var img = premul.copy ();
            unpremultiply (img);
            ColorManagement.convert (img, from, to);
            premultiply (img);
            return img;
        }

        public Gdk.Texture to_display_texture_managed (FloatImage premul, string working, string display, bool checker) {
            if ((working == "linear-srgb" || working == "") && (display == "srgb" || display == "")) return to_display_texture (premul, null, checker);
            var lin = working == "linear-srgb" ? premul : convert_space (premul, working, "linear-srgb");
            int w = lin.width, h = lin.height;
            var flat = new FloatImage (w, h);
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    size_t i = lin.offset (x, y);
                    float a = lin.data[i + 3].clamp (0, 1);
                    bool light = ((x / 8) + (y / 8)) % 2 == 0;
                    float bg = checker ? Transfer.srgb_to_linear (light ? 0.42f : 0.27f) : 0;
                    for (int c = 0; c < 3; c++) flat.data[i + c] = lin.data[i + c] + bg * (1 - a);
                    flat.data[i + 3] = 1;
                }
            ColorManagement.convert (flat, "linear-srgb", display);
            var px = new uint8[(size_t) w * h * 4];
            for (size_t i = 0; i < (size_t) w * h; i++) {
                for (int c = 0; c < 3; c++) px[i * 4 + c] = (uint8) (flat.data[i * 4 + c].clamp (0, 1) * 255 + 0.5f);
                px[i * 4 + 3] = 255;
            }
            return new Gdk.MemoryTexture (w, h, Gdk.MemoryFormat.R8G8B8A8, new Bytes.take ((owned) px), w * 4);
        }

        public Gdk.Texture to_display_texture (FloatImage premul, double[]? background, bool checker) {
            int w = premul.width, h = premul.height;
            var px = new uint8[(size_t) w * h * 4];
            Parallel.range (h, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < w; x++) {
                        size_t i = premul.offset (x, y);
                        float a = premul.data[i + 3].clamp (0, 1);
                        float br, bg, bb;
                        if (background != null && !checker) {
                            br = (float) background[0];
                            bg = (float) background[1];
                            bb = (float) background[2];
                        } else {
                            bool light = ((x / 8) + (y / 8)) % 2 == 0;
                            br = bg = bb = light ? 0.42f : 0.27f;
                        }
                        float r = premul.data[i] + br * (1 - a);
                        float g = premul.data[i + 1] + bg * (1 - a);
                        float b = premul.data[i + 2] + bb * (1 - a);
                        size_t o = ((size_t) y * w + x) * 4;
                        px[o] = Transfer.encode_byte (r);
                        px[o + 1] = Transfer.encode_byte (g);
                        px[o + 2] = Transfer.encode_byte (b);
                        px[o + 3] = 255;
                    }
            });
            return new Gdk.MemoryTexture (w, h, Gdk.MemoryFormat.R8G8B8A8, new Bytes.take ((owned) px), w * 4);
        }
    }
}
