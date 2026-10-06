using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace EffectsKeying {
        public float[] straight_display (FloatImage img) {
            size_t n = img.pixel_count ();
            var out_px = new float[n * 4];
            for (size_t i = 0; i < n; i++) {
                float a = img.data[i * 4 + 3];
                out_px[i * 4 + 3] = a;
                if (a <= 1e-6f) continue;
                for (int c = 0; c < 3; c++) out_px[i * 4 + c] = Transfer.linear_to_srgb ((img.data[i * 4 + c] / a).clamp (0, 1));
            }
            return out_px;
        }

        public void write_back (FloatImage img, float[] disp, float[] alpha) {
            size_t n = img.pixel_count ();
            for (size_t i = 0; i < n; i++) {
                float a = alpha[i].clamp (0, 1);
                for (int c = 0; c < 3; c++) img.data[i * 4 + c] = Transfer.srgb_to_linear (disp[i * 4 + c].clamp (0, 1)) * a;
                img.data[i * 4 + 3] = a;
            }
        }

        public void refine (float[] alpha, int w, int h, double choke_px, double soften_px, double contrast) {
            if (choke_px.abs () > 0.01) {
                var sd = DistanceField.signed_distance (alpha, w, h);
                for (size_t i = 0; i < alpha.length; i++) {
                    float lim = ((float) (sd[i] - choke_px) + 0.5f).clamp (0, 1);
                    alpha[i] = choke_px > 0 ? float.min (alpha[i], lim) : float.max (alpha[i], lim);
                }
            }
            if (soften_px > 0.05) Blur.gaussian_plane (alpha, w, h, soften_px / 2, soften_px / 2);
            if (contrast > 0.001) {
                float k = (float) (1 + contrast * 4);
                for (size_t i = 0; i < alpha.length; i++) alpha[i] = ((alpha[i] - 0.5f) * k + 0.5f).clamp (0, 1);
            }
        }

        private int dominant (double[] s) {
            if (s[1] >= s[0] && s[1] >= s[2]) return 1;
            if (s[2] >= s[0] && s[2] >= s[1]) return 2;
            return 0;
        }

        public void register () {
            EffectRegistry.add (new EffectDef ("color-key", _("Color Key"), _("Keying"), (g) => {
                g.add<Property> (Factory.color ("key-color", _("Key Color"), { 0, 1, 0, 1 }));
                g.add<Property> (Factory.scalar ("tolerance", _("Color Tolerance"), 40).range (0, 255));
                g.add<Property> (Factory.scalar ("edge-thin", _("Edge Thin"), 0).range (-5, 5));
                g.add<Property> (Factory.scalar ("edge-feather", _("Edge Feather"), 0).range (0, 50));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var disp = straight_display (img);
                var kc = fx.vec ("key-color", t);
                double kr = Transfer.linear_to_srgb ((float) kc[0]), kg = Transfer.linear_to_srgb ((float) kc[1]), kb = Transfer.linear_to_srgb ((float) kc[2]);
                double tol = fx.num ("tolerance", t) / 255.0;
                size_t n = img.pixel_count ();
                var alpha = new float[n];
                for (size_t i = 0; i < n; i++) {
                    double d = Math.fmax (Math.fmax ((disp[i * 4] - kr).abs (), (disp[i * 4 + 1] - kg).abs ()), (disp[i * 4 + 2] - kb).abs ());
                    alpha[i] = d <= tol ? 0 : disp[i * 4 + 3];
                }
                refine (alpha, img.width, img.height, ctx.px (fx.num ("edge-thin", t)), ctx.px (fx.num ("edge-feather", t)), 0);
                write_back (img, disp, alpha);
            }));

            EffectRegistry.add (new EffectDef ("linear-color-key", _("Linear Color Key"), _("Keying"), (g) => {
                g.add<Property> (Factory.color ("key-color", _("Key Color"), { 0, 0, 1, 1 }));
                g.add<Property> (Factory.choice ("space", _("Match colors"), { _("Using RGB"), _("Using Hue"), _("Using Chroma") }));
                g.add<Property> (Factory.percent ("tolerance", _("Matching Tolerance"), 10).range (0, 100));
                g.add<Property> (Factory.percent ("softness", _("Matching Softness"), 10).range (0, 100));
                g.add<Property> (Factory.choice ("operation", _("Key Operation"), { _("Key Colors"), _("Keep Colors") }));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var disp = straight_display (img);
                var kc = fx.vec ("key-color", t);
                float kr = Transfer.linear_to_srgb ((float) kc[0]), kg = Transfer.linear_to_srgb ((float) kc[1]), kb = Transfer.linear_to_srgb ((float) kc[2]);
                float kh, ks, kl;
                FxUtil.rgb_to_hsl (kr, kg, kb, out kh, out ks, out kl);
                int space = fx.choice ("space", t);
                double tol = fx.num ("tolerance", t) / 100.0, soft = fx.num ("softness", t) / 100.0;
                bool keep = fx.choice ("operation", t) == 1;
                size_t n = img.pixel_count ();
                var alpha = new float[n];
                for (size_t i = 0; i < n; i++) {
                    float r = disp[i * 4], g2 = disp[i * 4 + 1], b = disp[i * 4 + 2];
                    double d;
                    if (space == 1) {
                        float h, s, l;
                        FxUtil.rgb_to_hsl (r, g2, b, out h, out s, out l);
                        double dh = (h - kh).abs ();
                        d = double.min (dh, 1 - dh) * 2;
                        if (s < 0.05) d = 1;
                    } else if (space == 2) {
                        float sum = float.max (1e-4f, r + g2 + b), ksum = float.max (1e-4f, kr + kg + kb);
                        d = Math.hypot (r / sum - kr / ksum, g2 / sum - kg / ksum) * 2;
                    } else {
                        d = Math.sqrt ((r - kr) * (r - kr) + (g2 - kg) * (g2 - kg) + (b - kb) * (b - kb)) / Math.sqrt (3);
                    }
                    double m = soft > 0 ? ((d - tol) / soft).clamp (0, 1) : (d > tol ? 1 : 0);
                    if (keep) m = 1 - m;
                    alpha[i] = disp[i * 4 + 3] * (float) m;
                }
                write_back (img, disp, alpha);
            }));

            EffectRegistry.add (new EffectDef ("luma-key", _("Luma Key"), _("Keying"), (g) => {
                g.add<Property> (Factory.choice ("type", _("Key Type"), { _("Key Out Brighter"), _("Key Out Darker"), _("Key Out Similar"), _("Key Out Dissimilar") }, 1));
                g.add<Property> (Factory.scalar ("threshold", _("Threshold"), 0).range (0, 255));
                g.add<Property> (Factory.scalar ("tolerance", _("Tolerance"), 0).range (0, 255));
                g.add<Property> (Factory.scalar ("edge-thin", _("Edge Thin"), 0).range (-5, 5));
                g.add<Property> (Factory.scalar ("edge-feather", _("Edge Feather"), 0).range (0, 50));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var disp = straight_display (img);
                int type = fx.choice ("type", t);
                double th = fx.num ("threshold", t) / 255.0, tol = fx.num ("tolerance", t) / 255.0;
                size_t n = img.pixel_count ();
                var alpha = new float[n];
                for (size_t i = 0; i < n; i++) {
                    double l = 0.299 * disp[i * 4] + 0.587 * disp[i * 4 + 1] + 0.114 * disp[i * 4 + 2];
                    bool out_key;
                    switch (type) {
                        case 0: out_key = l > th; break;
                        case 2: out_key = (l - th).abs () <= tol; break;
                        case 3: out_key = (l - th).abs () > tol; break;
                        default: out_key = l < th; break;
                    }
                    alpha[i] = out_key ? 0 : disp[i * 4 + 3];
                }
                refine (alpha, img.width, img.height, ctx.px (fx.num ("edge-thin", t)), ctx.px (fx.num ("edge-feather", t)), 0);
                write_back (img, disp, alpha);
            }));

            EffectRegistry.add (new EffectDef ("keylight", _("Keylight"), _("Keying"), (g) => {
                g.add<Property> (Factory.choice ("view", _("View"), { _("Final Result"), _("Combined Matte"), _("Status"), _("Screen Matte") }));
                g.add<Property> (Factory.color ("screen-color", _("Screen Colour"), { 0.1, 0.75, 0.15, 1 }));
                g.add<Property> (Factory.scalar ("screen-gain", _("Screen Gain"), 100).range (0, 200));
                g.add<Property> (Factory.scalar ("screen-balance", _("Screen Balance"), 50).range (0, 100));
                g.add<Property> (Factory.color ("despill-bias", _("Despill Bias"), { 0.5, 0.5, 0.5, 1 }));
                g.add<Property> (Factory.color ("alpha-bias", _("Alpha Bias"), { 0.5, 0.5, 0.5, 1 }));
                g.add<Property> (Factory.toggle ("despill", _("Despill"), true));
                g.add<Property> (Factory.scalar ("clip-black", _("Clip Black"), 0).range (0, 100));
                g.add<Property> (Factory.scalar ("clip-white", _("Clip White"), 100).range (0, 100));
                g.add<Property> (Factory.scalar ("shrink-grow", _("Screen Shrink/Grow"), 0).range (-50, 50).ui_range (-10, 10));
                g.add<Property> (Factory.scalar ("softness", _("Screen Softness"), 0).range (0, 100).ui_range (0, 20));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var disp = straight_display (img);
                var sc = fx.vec ("screen-color", t);
                double[] s = { Transfer.linear_to_srgb ((float) sc[0]), Transfer.linear_to_srgb ((float) sc[1]), Transfer.linear_to_srgb ((float) sc[2]) };
                int d = dominant (s);
                int o1 = (d + 1) % 3, o2 = (d + 2) % 3;
                double bal = fx.num ("screen-balance", t) / 100.0;
                double gain = fx.num ("screen-gain", t) / 100.0;
                double sdiff = s[d] - (bal * s[o1] + (1 - bal) * s[o2]);
                if (sdiff < 1e-4) sdiff = 1e-4;
                var ab = fx.vec ("alpha-bias", t);
                double abal = (ab[o1] + ab[o2]) > 0 ? ab[o1] / (ab[o1] + ab[o2]) : 0.5;
                double cb = fx.num ("clip-black", t) / 100.0, cw = fx.num ("clip-white", t) / 100.0;
                if (cw <= cb) cw = cb + 1e-3;
                size_t n = img.pixel_count ();
                var alpha = new float[n];
                var screen = new float[n];
                for (size_t i = 0; i < n; i++) {
                    double c_d = disp[i * 4 + d], c1 = disp[i * 4 + o1], c2 = disp[i * 4 + o2];
                    double mix_other = (bal * 0.5 + abal * 0.5) * c1 + (1 - (bal * 0.5 + abal * 0.5)) * c2;
                    double diff = c_d - mix_other;
                    double a = 1 - (diff / sdiff * gain).clamp (0, 1);
                    screen[i] = (float) a;
                    a = ((a - cb) / (cw - cb)).clamp (0, 1);
                    alpha[i] = (float) a * disp[i * 4 + 3];
                }
                refine (alpha, img.width, img.height, -ctx.px (fx.num ("shrink-grow", t)), ctx.px (fx.num ("softness", t)), 0);
                if (fx.toggle ("despill", t)) {
                    var db = fx.vec ("despill-bias", t);
                    double dbal = (db[o1] + db[o2]) > 0 ? db[o1] / (db[o1] + db[o2]) : 0.5;
                    for (size_t i = 0; i < n; i++) {
                        double limit = dbal * disp[i * 4 + o1] + (1 - dbal) * disp[i * 4 + o2];
                        if (disp[i * 4 + d] > limit) disp[i * 4 + d] = (float) limit;
                    }
                }
                int view = fx.choice ("view", t);
                if (view == 0) {
                    write_back (img, disp, alpha);
                    return;
                }
                for (size_t i = 0; i < n; i++) {
                    float v;
                    if (view == 1) v = alpha[i];
                    else if (view == 3) v = screen[i];
                    else v = alpha[i] <= 0.001f ? 0 : (alpha[i] >= 0.999f ? 1 : 0.5f);
                    float lin = Transfer.srgb_to_linear (v);
                    img.data[i * 4] = lin;
                    img.data[i * 4 + 1] = lin;
                    img.data[i * 4 + 2] = lin;
                    img.data[i * 4 + 3] = 1;
                }
            }));

            EffectRegistry.add (new EffectDef ("spill-suppressor", _("Spill Suppressor"), _("Keying"), (g) => {
                g.add<Property> (Factory.color ("color", _("Color To Suppress"), { 0, 1, 0, 1 }));
                g.add<Property> (Factory.percent ("amount", _("Suppression"), 100).range (0, 200));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var disp = straight_display (img);
                var c = fx.vec ("color", t);
                int d = dominant (c);
                int o1 = (d + 1) % 3, o2 = (d + 2) % 3;
                float amt = (float) (fx.num ("amount", t) / 100.0);
                size_t n = img.pixel_count ();
                var alpha = new float[n];
                for (size_t i = 0; i < n; i++) {
                    alpha[i] = disp[i * 4 + 3];
                    float avg = (disp[i * 4 + o1] + disp[i * 4 + o2]) / 2;
                    float excess = float.max (0, disp[i * 4 + d] - avg);
                    disp[i * 4 + d] -= excess * float.min (1, amt);
                }
                write_back (img, disp, alpha);
            }));

            EffectRegistry.add (new EffectDef ("matte-refine", _("Refine Matte"), _("Keying"), (g) => {
                g.add<Property> (Factory.scalar ("choke", _("Choke"), 0).range (-100, 100).ui_range (-20, 20));
                g.add<Property> (Factory.scalar ("soften", _("Soften"), 0).range (0, 100).ui_range (0, 20));
                g.add<Property> (Factory.percent ("contrast", _("Contrast"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var disp = straight_display (img);
                size_t n = img.pixel_count ();
                var alpha = new float[n];
                for (size_t i = 0; i < n; i++) alpha[i] = disp[i * 4 + 3];
                refine (alpha, img.width, img.height, ctx.px (fx.num ("choke", t)), ctx.px (fx.num ("soften", t)), fx.num ("contrast", t) / 100.0);
                write_back (img, disp, alpha);
            }, (fx, t) => double.max (0, -fx.num ("choke", t)) + fx.num ("soften", t)));
        }
    }
}
