using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace EffectsColor {
        public delegate void DisplayFunc (ref float r, ref float g, ref float b);

        public void per_display (FloatImage img, DisplayFunc f) {
            FxUtil.per_pixel (img, (ref r, ref g, ref b, ref a) => {
                float er = Transfer.linear_to_srgb (r.clamp (0, 1)), eg = Transfer.linear_to_srgb (g.clamp (0, 1)), eb = Transfer.linear_to_srgb (b.clamp (0, 1));
                float hr = float.max (0, r - 1), hg = float.max (0, g - 1), hb = float.max (0, b - 1);
                f (ref er, ref eg, ref eb);
                r = Transfer.srgb_to_linear (er.clamp (0, 1)) + hr;
                g = Transfer.srgb_to_linear (eg.clamp (0, 1)) + hg;
                b = Transfer.srgb_to_linear (eb.clamp (0, 1)) + hb;
            });
        }

        public class CurvePoints {
            public double[] xs = { 0, 1 };
            public double[] ys = { 0, 1 };

            public static CurvePoints parse (string s) {
                var c = new CurvePoints ();
                double[] xs = {}, ys = {};
                foreach (var pair in s.strip ().split (" ")) {
                    var p = pair.split (",");
                    if (p.length != 2) continue;
                    xs += double.parse (p[0]);
                    ys += double.parse (p[1]);
                }
                if (xs.length >= 2) {
                    c.xs = xs;
                    c.ys = ys;
                }
                return c;
            }

            public float eval (float x) {
                int n = xs.length;
                if (x <= xs[0]) return (float) ys[0];
                if (x >= xs[n - 1]) return (float) ys[n - 1];
                int i = 0;
                while (i < n - 2 && x > xs[i + 1]) i++;
                double h = xs[i + 1] - xs[i];
                if (h <= 0) return (float) ys[i];
                double m0 = slope (i), m1 = slope (i + 1);
                double t = (x - xs[i]) / h;
                double t2 = t * t, t3 = t2 * t;
                return (float) ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m0 + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m1).clamp (0, 1);
            }

            private double slope (int i) {
                int n = xs.length;
                if (i == 0) return (ys[1] - ys[0]) / double.max (1e-9, xs[1] - xs[0]);
                if (i == n - 1) return (ys[n - 1] - ys[n - 2]) / double.max (1e-9, xs[n - 1] - xs[n - 2]);
                return (ys[i + 1] - ys[i - 1]) / double.max (1e-9, xs[i + 1] - xs[i - 1]);
            }
        }

        public void register () {
            EffectRegistry.add (new EffectDef ("brightness-contrast", _("Brightness & Contrast"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.scalar ("brightness", _("Brightness"), 0).range (-150, 150));
                g.add<Property> (Factory.scalar ("contrast", _("Contrast"), 0).range (-100, 100));
            }, (ctx, fx, t) => {
                float br = (float) (fx.num ("brightness", t) / 150.0 * 0.5);
                float co = (float) (fx.num ("contrast", t) / 100.0);
                float k = co >= 0 ? 1 / float.max (0.01f, 1 - co) : 1 + co;
                per_display (ctx.buf.img, (ref r, ref g, ref b) => {
                    r = (r + br - 0.5f) * k + 0.5f;
                    g = (g + br - 0.5f) * k + 0.5f;
                    b = (b + br - 0.5f) * k + 0.5f;
                });
            }));

            EffectRegistry.add (new EffectDef ("hue-saturation", _("Hue/Saturation"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.angle ("hue", _("Master Hue"), 0));
                g.add<Property> (Factory.scalar ("saturation", _("Master Saturation"), 0).range (-100, 100));
                g.add<Property> (Factory.scalar ("lightness", _("Master Lightness"), 0).range (-100, 100));
                g.add<Property> (Factory.toggle ("colorize", _("Colorize"), false));
                g.add<Property> (Factory.angle ("colorize-hue", _("Colorize Hue"), 0));
                g.add<Property> (Factory.scalar ("colorize-saturation", _("Colorize Saturation"), 25).range (0, 100));
            }, (ctx, fx, t) => {
                float dh = (float) (fx.num ("hue", t) / 360.0);
                float ds = (float) (fx.num ("saturation", t) / 100.0);
                float dl = (float) (fx.num ("lightness", t) / 100.0);
                bool colorize = fx.toggle ("colorize", t);
                float ch = (float) (fx.num ("colorize-hue", t) / 360.0), cs = (float) (fx.num ("colorize-saturation", t) / 100.0);
                per_display (ctx.buf.img, (ref r, ref g, ref b) => {
                    float h, s, l;
                    FxUtil.rgb_to_hsl (r, g, b, out h, out s, out l);
                    if (colorize) {
                        h = ch;
                        s = cs;
                    } else {
                        h = h + dh;
                        h -= Math.floorf (h);
                        s = ds >= 0 ? s + (1 - s) * ds * s : s * (1 + ds);
                    }
                    l = dl >= 0 ? l + (1 - l) * dl : l * (1 + dl);
                    FxUtil.hsl_to_rgb (h, s.clamp (0, 1), l.clamp (0, 1), out r, out g, out b);
                });
            }));

            EffectRegistry.add (new EffectDef ("levels", _("Levels"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.choice ("channel", _("Channel"), { _("RGB"), _("Red"), _("Green"), _("Blue"), _("Alpha") }));
                g.add<Property> (Factory.scalar ("input-black", _("Input Black"), 0).range (0, 1).ui_range (0, 1));
                g.add<Property> (Factory.scalar ("input-white", _("Input White"), 1).range (0, 1).ui_range (0, 1));
                g.add<Property> (Factory.scalar ("gamma", _("Gamma"), 1).range (0.1, 10).ui_range (0.1, 4));
                g.add<Property> (Factory.scalar ("output-black", _("Output Black"), 0).range (0, 1).ui_range (0, 1));
                g.add<Property> (Factory.scalar ("output-white", _("Output White"), 1).range (0, 1).ui_range (0, 1));
            }, (ctx, fx, t) => {
                int ch = fx.choice ("channel", t);
                float ib = (float) fx.num ("input-black", t), iw = (float) fx.num ("input-white", t);
                float gm = (float) fx.num ("gamma", t), ob = (float) fx.num ("output-black", t), ow = (float) fx.num ("output-white", t);
                float span = float.max (1e-5f, iw - ib);
                if (ch == 4) {
                    var img = ctx.buf.img;
                    size_t n = img.pixel_count ();
                    for (size_t i = 0; i < n; i++) {
                        float a = img.data[i * 4 + 3];
                        float na = ob + (ow - ob) * Math.powf (((a - ib) / span).clamp (0, 1), 1 / gm);
                        float k = a > 1e-6f ? na / a : 0;
                        for (int c = 0; c < 3; c++) img.data[i * 4 + c] *= k;
                        img.data[i * 4 + 3] = na;
                    }
                    return;
                }
                per_display (ctx.buf.img, (ref r, ref g, ref b) => {
                    if (ch == 0 || ch == 1) r = ob + (ow - ob) * Math.powf (((r - ib) / span).clamp (0, 1), 1 / gm);
                    if (ch == 0 || ch == 2) g = ob + (ow - ob) * Math.powf (((g - ib) / span).clamp (0, 1), 1 / gm);
                    if (ch == 0 || ch == 3) b = ob + (ow - ob) * Math.powf (((b - ib) / span).clamp (0, 1), 1 / gm);
                });
            }));

            EffectRegistry.add (new EffectDef ("curves", _("Curves"), _("Color Correction"), (g) => {
                g.attrs["rgb"] = "0,0 1,1";
                g.attrs["red"] = "0,0 1,1";
                g.attrs["green"] = "0,0 1,1";
                g.attrs["blue"] = "0,0 1,1";
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var master = CurvePoints.parse (fx.attr ("rgb", "0,0 1,1"));
                var cr = CurvePoints.parse (fx.attr ("red", "0,0 1,1"));
                var cg = CurvePoints.parse (fx.attr ("green", "0,0 1,1"));
                var cb = CurvePoints.parse (fx.attr ("blue", "0,0 1,1"));
                var lut = new float[3 * 1024];
                for (int i = 0; i < 1024; i++) {
                    float x = i / 1023.0f;
                    lut[i] = cr.eval (master.eval (x));
                    lut[1024 + i] = cg.eval (master.eval (x));
                    lut[2048 + i] = cb.eval (master.eval (x));
                }
                var orig = ctx.buf.img.copy ();
                per_display (ctx.buf.img, (ref r, ref g, ref b) => {
                    r = lut[(int) (r.clamp (0, 1) * 1023)];
                    g = lut[1024 + (int) (g.clamp (0, 1) * 1023)];
                    b = lut[2048 + (int) (b.clamp (0, 1) * 1023)];
                });
                FxUtil.mix_original (ctx.buf.img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("exposure", _("Exposure"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.scalar ("exposure", _("Exposure"), 0).range (-20, 20).ui_range (-5, 5));
                g.add<Property> (Factory.scalar ("offset", _("Offset"), 0).range (-2, 2).ui_range (-0.5, 0.5));
                g.add<Property> (Factory.scalar ("gamma", _("Gamma Correction"), 1).range (0.01, 10).ui_range (0.1, 3));
            }, (ctx, fx, t) => {
                float k = Math.powf (2, (float) fx.num ("exposure", t));
                float off = (float) fx.num ("offset", t);
                float gm = (float) fx.num ("gamma", t);
                FxUtil.per_pixel (ctx.buf.img, (ref r, ref g, ref b, ref a) => {
                    r = Math.powf (float.max (0, r * k + off), 1 / gm);
                    g = Math.powf (float.max (0, g * k + off), 1 / gm);
                    b = Math.powf (float.max (0, b * k + off), 1 / gm);
                });
            }));

            EffectRegistry.add (new EffectDef ("tint", _("Tint"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.color ("black", _("Map Black To"), { 0, 0, 0, 1 }));
                g.add<Property> (Factory.color ("white", _("Map White To"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.percent ("amount", _("Amount to Tint"), 100).range (0, 100));
            }, (ctx, fx, t) => {
                var bl = fx.vec ("black", t);
                var wh = fx.vec ("white", t);
                float amt = (float) (fx.num ("amount", t) / 100.0);
                FxUtil.per_pixel (ctx.buf.img, (ref r, ref g, ref b, ref a) => {
                    float l = Pixels.luma (r, g, b).clamp (0, 1);
                    l = Transfer.linear_to_srgb (l);
                    float tr = (float) (bl[0] + (wh[0] - bl[0]) * l), tg = (float) (bl[1] + (wh[1] - bl[1]) * l), tb = (float) (bl[2] + (wh[2] - bl[2]) * l);
                    r += (tr - r) * amt;
                    g += (tg - g) * amt;
                    b += (tb - b) * amt;
                });
            }));

            EffectRegistry.add (new EffectDef ("tritone", _("Tritone"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.color ("highlights", _("Highlights"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.color ("midtones", _("Midtones"), { 0.43, 0.32, 0.18, 1 }));
                g.add<Property> (Factory.color ("shadows", _("Shadows"), { 0, 0, 0, 1 }));
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var hi = fx.vec ("highlights", t);
                var mi = fx.vec ("midtones", t);
                var sh = fx.vec ("shadows", t);
                var orig = ctx.buf.img.copy ();
                per_display (ctx.buf.img, (ref r, ref g, ref b) => {
                    float l = 0.299f * r + 0.587f * g + 0.114f * b;
                    double[] lo, up;
                    double u;
                    if (l < 0.5f) {
                        lo = sh;
                        up = mi;
                        u = l * 2;
                    } else {
                        lo = mi;
                        up = hi;
                        u = (l - 0.5) * 2;
                    }
                    r = (float) (Transfer.linear_to_srgb ((float) (lo[0] + (up[0] - lo[0]) * u)));
                    g = (float) (Transfer.linear_to_srgb ((float) (lo[1] + (up[1] - lo[1]) * u)));
                    b = (float) (Transfer.linear_to_srgb ((float) (lo[2] + (up[2] - lo[2]) * u)));
                });
                FxUtil.mix_original (ctx.buf.img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("color-balance", _("Color Balance"), _("Color Correction"), (g) => {
                foreach (var tone in new string[] { "shadow", "midtone", "highlight" }) {
                    g.add<Property> (Factory.scalar (tone + "-red", tone == "shadow" ? _("Shadow Red Balance") : (tone == "midtone" ? _("Midtone Red Balance") : _("Highlight Red Balance")), 0).range (-100, 100));
                    g.add<Property> (Factory.scalar (tone + "-green", tone == "shadow" ? _("Shadow Green Balance") : (tone == "midtone" ? _("Midtone Green Balance") : _("Highlight Green Balance")), 0).range (-100, 100));
                    g.add<Property> (Factory.scalar (tone + "-blue", tone == "shadow" ? _("Shadow Blue Balance") : (tone == "midtone" ? _("Midtone Blue Balance") : _("Highlight Blue Balance")), 0).range (-100, 100));
                }
            }, (ctx, fx, t) => {
                double[] sv = { fx.num ("shadow-red", t), fx.num ("shadow-green", t), fx.num ("shadow-blue", t) };
                double[] mv = { fx.num ("midtone-red", t), fx.num ("midtone-green", t), fx.num ("midtone-blue", t) };
                double[] hv = { fx.num ("highlight-red", t), fx.num ("highlight-green", t), fx.num ("highlight-blue", t) };
                per_display (ctx.buf.img, (ref r, ref g, ref b) => {
                    float[] c = { r, g, b };
                    for (int k = 0; k < 3; k++) {
                        float v = c[k];
                        float ws = (1 - v) * (1 - v), wh = v * v, wm = 1 - ws - wh;
                        c[k] = v + (float) ((sv[k] * ws + mv[k] * wm + hv[k] * wh) / 100.0 * 0.5);
                    }
                    r = c[0];
                    g = c[1];
                    b = c[2];
                });
            }));

            EffectRegistry.add (new EffectDef ("channel-mixer", _("Channel Mixer"), _("Color Correction"), (g) => {
                string[] outs = { "red", "green", "blue" };
                string[] labels = { _("Red-Red"), _("Red-Green"), _("Red-Blue"), _("Green-Red"), _("Green-Green"), _("Green-Blue"), _("Blue-Red"), _("Blue-Green"), _("Blue-Blue") };
                int li = 0;
                foreach (var o in outs)
                    foreach (var i in outs) {
                        g.add<Property> (Factory.scalar (o + "-" + i, labels[li++], o == i ? 100 : 0).range (-200, 200));
                    }
                g.add<Property> (Factory.toggle ("monochrome", _("Monochrome"), false));
            }, (ctx, fx, t) => {
                var m = new double[9];
                string[] outs = { "red", "green", "blue" };
                for (int o = 0; o < 3; o++)
                    for (int i = 0; i < 3; i++) m[o * 3 + i] = fx.num (outs[o] + "-" + outs[i], t) / 100.0;
                bool mono = fx.toggle ("monochrome", t);
                FxUtil.per_pixel (ctx.buf.img, (ref r, ref g, ref b, ref a) => {
                    float nr = (float) (m[0] * r + m[1] * g + m[2] * b);
                    float ng = (float) (m[3] * r + m[4] * g + m[5] * b);
                    float nb = (float) (m[6] * r + m[7] * g + m[8] * b);
                    if (mono) ng = nb = nr;
                    r = float.max (0, nr);
                    g = float.max (0, ng);
                    b = float.max (0, nb);
                });
            }));

            EffectRegistry.add (new EffectDef ("black-white", _("Black & White"), _("Color Correction"), (g) => {
                g.add<Property> (Factory.toggle ("tint", _("Tint"), false));
                g.add<Property> (Factory.color ("tint-color", _("Tint Color"), { 0.9, 0.8, 0.6, 1 }));
            }, (ctx, fx, t) => {
                bool tint = fx.toggle ("tint", t);
                var tc = fx.vec ("tint-color", t);
                FxUtil.per_pixel (ctx.buf.img, (ref r, ref g, ref b, ref a) => {
                    float l = Pixels.luma (r, g, b);
                    r = tint ? l * (float) tc[0] : l;
                    g = tint ? l * (float) tc[1] : l;
                    b = tint ? l * (float) tc[2] : l;
                });
            }));

            EffectRegistry.add (new EffectDef ("color-lut", _("Apply Color LUT"), _("Color Correction"), (g) => {
                g.attrs["file"] = "";
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var path = fx.attr ("file", "");
                if (path == "") return;
                Lut3D lut;
                try {
                    string text;
                    FileUtils.get_contents (ctx.renderer.project.resolve_path (path), out text);
                    lut = Lut3D.parse_cube (text);
                } catch (Error e) {
                    return;
                }
                var orig = ctx.buf.img.copy ();
                per_display (ctx.buf.img, (ref r, ref g, ref b) => lut.apply (ref r, ref g, ref b));
                FxUtil.mix_original (ctx.buf.img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("color-convert", _("Color Space Transform"), _("Color Correction"), (g) => {
                g.attrs["from"] = "srgb";
                g.attrs["to"] = "linear-srgb";
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                Pixels.unpremultiply (img);
                ColorManagement.convert (img, fx.attr ("from", "srgb"), fx.attr ("to", "linear-srgb"));
                Pixels.premultiply (img);
            }));
        }
    }
}
