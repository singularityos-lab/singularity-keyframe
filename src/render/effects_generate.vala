using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace EffectsGenerate {
        public string[] blend_labels () {
            return { _("None"), _("Normal"), _("Add"), _("Multiply"), _("Screen"), _("Overlay"), _("Soft Light"), _("Stencil Alpha") };
        }

        public void compose (EffectContext ctx, FloatImage gen, double opacity, int mode) {
            var orig = ctx.buf.img;
            float op = (float) opacity.clamp (0, 1);
            if (mode == 0) {
                size_t n = orig.pixel_count () * 4;
                for (size_t i = 0; i < n; i++) gen.data[i] = gen.data[i] * op + orig.data[i] * (1 - op);
                ctx.buf.img = gen;
                return;
            }
            if (mode == 7) {
                size_t n = orig.pixel_count ();
                for (size_t i = 0; i < n; i++) {
                    float a = orig.data[i * 4 + 3];
                    for (int c = 0; c < 4; c++) gen.data[i * 4 + c] = (gen.data[i * 4 + c] * a) * op + orig.data[i * 4 + c] * (1 - op);
                }
                ctx.buf.img = gen;
                return;
            }
            Pixels.scale_alpha (gen, op);
            BlendMode bm;
            switch (mode) {
                case 2: bm = BlendMode.LINEAR_DODGE; break;
                case 3: bm = BlendMode.MULTIPLY; break;
                case 4: bm = BlendMode.SCREEN; break;
                case 5: bm = BlendMode.OVERLAY; break;
                case 6: bm = BlendMode.SOFT_LIGHT; break;
                default: bm = BlendMode.NORMAL; break;
            }
            Pixels.blend (orig, new CompImage (gen, 0, 0), bm, true, false);
        }

        public void set_premul (FloatImage img, size_t i, double r, double g, double b, double a) {
            img.data[i * 4] = (float) (r * a);
            img.data[i * 4 + 1] = (float) (g * a);
            img.data[i * 4 + 2] = (float) (b * a);
            img.data[i * 4 + 3] = (float) a;
        }

        private double smoothstep (double e0, double e1, double x) {
            if (e1 <= e0) return x >= e1 ? 1 : 0;
            double u = ((x - e0) / (e1 - e0)).clamp (0, 1);
            return u * u * (3 - 2 * u);
        }

        public double fractal_value (double x, double y, double evo, int type, int octaves, double sub_infl, double sub_scale, double sub_rot, double sub_ox, double sub_oy, int seed) {
            double sum = 0, amp = 1, norm = 0;
            double px = x, py = y;
            double cr = Math.cos (sub_rot), sr = Math.sin (sub_rot);
            for (int o = 0; o < int.max (1, octaves); o++) {
                double n = Noise.perlin3 (px, py, evo + o * 3.7, seed + o * 17);
                if (type == 1) n = n.abs () * 2 - 1;
                else if (type == 2) n = (1 - n.abs ()) * 2 - 1;
                sum += n * amp;
                norm += amp;
                amp *= sub_infl;
                double nx = (px * cr - py * sr) * sub_scale + sub_ox, ny = (px * sr + py * cr) * sub_scale + sub_oy;
                px = nx;
                py = ny;
            }
            double v = norm > 0 ? sum / norm : 0;
            if (type == 2) v = Math.pow ((v * 0.5 + 0.5).clamp (0, 1), 2) * 2 - 1;
            return v * 0.5 + 0.5;
        }

        public void register () {
            EffectRegistry.add (new EffectDef ("fractal-noise", _("Fractal Noise"), _("Noise & Grain"), (g) => {
                g.add<Property> (Factory.choice ("type", _("Fractal Type"), { _("Basic"), _("Turbulent Smooth"), _("Turbulent Sharp") }, 1));
                g.add<Property> (Factory.toggle ("invert", _("Invert"), false));
                g.add<Property> (Factory.scalar ("contrast", _("Contrast"), 100).range (0, 10000).ui_range (0, 400));
                g.add<Property> (Factory.scalar ("brightness", _("Brightness"), 0).range (-10000, 10000).ui_range (-200, 200));
                g.add<Property> (Factory.choice ("overflow", _("Overflow"), { _("Clip"), _("Soft Clamp"), _("Wrap Back") }, 0));
                g.add<Property> (Factory.angle ("rotation", _("Rotation"), 0));
                g.add<Property> (Factory.scalar ("scale", _("Scale"), 100).range (1, 10000).ui_range (10, 600));
                g.add<Property> (Factory.point ("offset", _("Offset Turbulence"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("complexity", _("Complexity"), 6).range (1, 20).ui_range (1, 10));
                g.add<Property> (Factory.scalar ("sub-influence", _("Sub Influence (%)"), 70).range (0, 100));
                g.add<Property> (Factory.scalar ("sub-scaling", _("Sub Scaling"), 56).range (10, 100));
                g.add<Property> (Factory.angle ("sub-rotation", _("Sub Rotation"), 0));
                g.add<Property> (Factory.point ("sub-offset", _("Sub Offset"), { 0, 0 }));
                g.add<Property> (Factory.angle ("evolution", _("Evolution"), 0));
                g.add<Property> (Factory.toggle ("cycle", _("Cycle Evolution"), false));
                g.add<Property> (Factory.scalar ("cycle-revolutions", _("Cycle (in Revolutions)"), 1).range (1, 100));
                g.add<Property> (Factory.scalar ("seed", _("Random Seed"), 0).range (0, 100000));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("blend", _("Blending Mode"), blend_labels (), 0));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                int type = fx.choice ("type", t);
                bool inv = fx.toggle ("invert", t);
                double contrast = fx.num ("contrast", t) / 100.0, bright = fx.num ("brightness", t) / 100.0;
                int overflow = fx.choice ("overflow", t);
                double rot = fx.num ("rotation", t) * Math.PI / 180.0;
                double scale = ctx.px (double.max (1, fx.num ("scale", t)));
                var off = fx.vec ("offset", t);
                double offx = ctx.px (off[0]), offy = ctx.px (off[1]);
                int octaves = (int) Math.round (fx.num ("complexity", t));
                double infl = fx.num ("sub-influence", t) / 100.0, ssc = 100.0 / double.max (10, fx.num ("sub-scaling", t));
                double srot = fx.num ("sub-rotation", t) * Math.PI / 180.0;
                var so = fx.vec ("sub-offset", t);
                double evo = fx.num ("evolution", t) / 360.0;
                bool cycle = fx.toggle ("cycle", t);
                double cyc = double.max (1, fx.num ("cycle-revolutions", t));
                int seed = (int) fx.num ("seed", t);
                double cr = Math.cos (-rot), sr = Math.sin (-rot);
                double cx = img.width / 2.0, cy = img.height / 2.0;
                Parallel.range (img.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < img.width; x++) {
                            double dx = x + 0.5 - cx - offx, dy = y + 0.5 - cy - offy;
                            double u = (dx * cr - dy * sr) / scale * 4, v = (dx * sr + dy * cr) / scale * 4;
                            double val;
                            if (cycle) {
                                double ep = evo - Math.floor (evo / cyc) * cyc;
                                double a = fractal_value (u, v, ep, type, octaves, infl, ssc, srot, so[0] / 100.0, so[1] / 100.0, seed);
                                double b = fractal_value (u, v, ep - cyc, type, octaves, infl, ssc, srot, so[0] / 100.0, so[1] / 100.0, seed);
                                val = a + (b - a) * (ep / cyc);
                            } else {
                                val = fractal_value (u, v, evo, type, octaves, infl, ssc, srot, so[0] / 100.0, so[1] / 100.0, seed);
                            }
                            val = (val - 0.5) * contrast + 0.5 + bright;
                            if (overflow == 1) val = 1 / (1 + Math.exp (-(val - 0.5) * 6));
                            else if (overflow == 2) {
                                double m = val - Math.floor (val / 2) * 2;
                                val = m > 1 ? 2 - m : m;
                            }
                            val = val.clamp (0, 1);
                            if (inv) val = 1 - val;
                            float lin = Transfer.srgb_to_linear ((float) val);
                            set_premul (gen, (size_t) y * img.width + x, lin, lin, lin, 1);
                        }
                });
                compose (ctx, gen, fx.num ("opacity", t) / 100.0, fx.choice ("blend", t));
            }));

            EffectRegistry.add (new EffectDef ("light-rays", _("Light Rays"), _("Stylize"), (g) => {
                g.add<Property> (Factory.scalar ("intensity", _("Intensity"), 100).range (0, 600).ui_range (0, 300));
                g.add<Property> (Factory.point ("center", _("Center"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("radius", _("Radius"), 40).range (0, 100));
                g.add<Property> (Factory.scalar ("warmth", _("Warmth"), 50).range (0, 100));
                g.add<Property> (Factory.choice ("transfer", _("Transfer Mode"), { _("Add"), _("None") }));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double reach = fx.num ("radius", t) / 100.0;
                double inten = fx.num ("intensity", t) / 100.0;
                double warm = fx.num ("warmth", t) / 100.0;
                bool add = fx.choice ("transfer", t) == 0;
                int steps = 24;
                var src = img.copy ();
                var rays = new FloatImage (img.width, img.height);
                Parallel.range (img.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < img.width; x++) {
                            float r = 0, g2 = 0, b = 0, a = 0;
                            for (int k = 0; k < steps; k++) {
                                double f = 1 - reach * k / (double) steps;
                                double sx = c[0] + (x + 0.5 - c[0]) * f, sy = c[1] + (y + 0.5 - c[1]) * f;
                                float pr, pg, pb, pa;
                                Pixels.sample_premul (src, sx, sy, out pr, out pg, out pb, out pa);
                                r += pr;
                                g2 += pg;
                                b += pb;
                                a += pa;
                            }
                            size_t o = rays.offset (x, y);
                            float k2 = (float) (inten / steps);
                            rays.data[o] = r * k2 * (float) (1 + warm * 0.2);
                            rays.data[o + 1] = g2 * k2 * (float) (1 - warm * 0.1);
                            rays.data[o + 2] = b * k2 * (float) (1 - warm * 0.4);
                            rays.data[o + 3] = (a * k2).clamp (0, 1);
                        }
                });
                if (add) {
                    size_t n = img.pixel_count ();
                    for (size_t i = 0; i < n; i++) {
                        for (int ch = 0; ch < 3; ch++) img.data[i * 4 + ch] += rays.data[i * 4 + ch];
                        float ra = rays.data[i * 4 + 3];
                        img.data[i * 4 + 3] = img.data[i * 4 + 3] + ra - img.data[i * 4 + 3] * ra;
                    }
                } else {
                    ctx.buf.img = rays;
                }
            }));

            EffectRegistry.add (new EffectDef ("lightning", _("Advanced Lightning"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("origin", _("Origin"), { 0, 0 }));
                g.add<Property> (Factory.point ("direction", _("Direction"), { 300, 300 }));
                g.add<Property> (Factory.scalar ("segments", _("Segments"), 7).range (1, 12));
                g.add<Property> (Factory.scalar ("amplitude", _("Amplitude"), 10).range (0, 100));
                g.add<Property> (Factory.percent ("branching", _("Branching"), 30).range (0, 100));
                g.add<Property> (Factory.percent ("rebranching", _("Rebranching"), 30).range (0, 100));
                g.add<Property> (Factory.scalar ("core-radius", _("Core Radius"), 2).range (0, 100).ui_range (0, 20));
                g.add<Property> (Factory.color ("core-color", _("Core Color"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.scalar ("glow-radius", _("Glow Radius"), 20).range (0, 400).ui_range (0, 100));
                g.add<Property> (Factory.color ("glow-color", _("Glow Color"), { 0.35, 0.45, 1, 1 }));
                g.add<Property> (Factory.angle ("conductivity", _("Conductivity State"), 0));
                g.add<Property> (Factory.scalar ("seed", _("Random Seed"), 1).range (0, 100000));
                g.add<Property> (Factory.toggle ("composite", _("Composite on Original"), true));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var o = FxUtil.point_in_pixels (ctx, fx, "origin");
                var d = FxUtil.point_in_pixels (ctx, fx, "direction");
                int depth = (int) Math.round (fx.num ("segments", t));
                double amp = fx.num ("amplitude", t) / 100.0;
                double branch = fx.num ("branching", t) / 100.0, rebranch = fx.num ("rebranching", t) / 100.0;
                double evo = fx.num ("conductivity", t) / 360.0;
                int seed = (int) fx.num ("seed", t);
                var surface = new Cairo.ImageSurface (Cairo.Format.A8, img.width, img.height);
                var cr = new Cairo.Context (surface);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                int counter = 0;
                bolt (cr, o[0], o[1], d[0], d[1], depth, amp, branch, rebranch, evo, seed, 1.0, ctx.px (double.max (0.5, fx.num ("core-radius", t))), ref counter);
                var core = Raster.read_a8 (surface);
                var glow = core.copy ();
                double gr = ctx.px (fx.num ("glow-radius", t)) / 2;
                if (gr > 0.3) Blur.gaussian_plane (glow, img.width, img.height, gr, gr);
                var cc = fx.vec ("core-color", t);
                var gc = fx.vec ("glow-color", t);
                var gen = new FloatImage (img.width, img.height);
                size_t n = gen.pixel_count ();
                for (size_t i = 0; i < n; i++) {
                    double ga = double.min (1, glow[i] * 3);
                    double ca = core[i];
                    double r = gc[0] * ga * (1 - ca) + cc[0] * ca, g2 = gc[1] * ga * (1 - ca) + cc[1] * ca, b = gc[2] * ga * (1 - ca) + cc[2] * ca;
                    double a = double.min (1, ca + ga * (1 - ca));
                    gen.data[i * 4] = (float) r;
                    gen.data[i * 4 + 1] = (float) g2;
                    gen.data[i * 4 + 2] = (float) b;
                    gen.data[i * 4 + 3] = (float) a;
                }
                if (fx.toggle ("composite", t)) Pixels.blend (img, new CompImage (gen, 0, 0), BlendMode.LINEAR_DODGE, true, false);
                else ctx.buf.img = gen;
            }));

            EffectRegistry.add (new EffectDef ("grid", _("Grid"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("anchor", _("Anchor"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("width", _("Width"), 64).range (1, 10000).ui_range (2, 500));
                g.add<Property> (Factory.scalar ("height", _("Height"), 64).range (1, 10000).ui_range (2, 500));
                g.add<Property> (Factory.scalar ("border", _("Border"), 2).range (0, 1000).ui_range (0, 50));
                g.add<Property> (Factory.scalar ("feather", _("Feather"), 0).range (0, 100));
                g.add<Property> (Factory.toggle ("invert", _("Invert Grid"), false));
                g.add<Property> (Factory.color ("color", _("Color"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("blend", _("Blending Mode"), blend_labels (), 1));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                var anc = FxUtil.point_in_pixels (ctx, fx, "anchor");
                double cw = ctx.px (double.max (1, fx.num ("width", t))), ch = ctx.px (double.max (1, fx.num ("height", t)));
                double border = ctx.px (fx.num ("border", t)) / 2, feather = ctx.px (fx.num ("feather", t));
                bool inv = fx.toggle ("invert", t);
                var col = fx.vec ("color", t);
                Parallel.range (img.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < img.width; x++) {
                            double mx = x + 0.5 - anc[0], my = y + 0.5 - anc[1];
                            double dx = (mx - Math.round (mx / cw) * cw).abs ();
                            double dy = (my - Math.round (my / ch) * ch).abs ();
                            double dmin = double.min (dx, dy);
                            double a = 1 - smoothstep (border - feather / 2 - 0.5, border + feather / 2 + 0.5, dmin);
                            if (inv) a = 1 - a;
                            set_premul (gen, (size_t) y * img.width + x, col[0], col[1], col[2], a * col[3]);
                        }
                });
                compose (ctx, gen, fx.num ("opacity", t) / 100.0, fx.choice ("blend", t));
            }));

            EffectRegistry.add (new EffectDef ("cell-pattern", _("Cell Pattern"), _("Generate"), (g) => {
                g.add<Property> (Factory.choice ("pattern", _("Cell Pattern"), { _("Bubbles"), _("Crystals"), _("Plates"), _("Static"), _("Mixed Crystals"), _("Tubular") }));
                g.add<Property> (Factory.toggle ("invert", _("Invert"), false));
                g.add<Property> (Factory.scalar ("contrast", _("Contrast"), 100).range (0, 10000).ui_range (0, 400));
                g.add<Property> (Factory.scalar ("disperse", _("Disperse"), 1).range (0, 1.5));
                g.add<Property> (Factory.scalar ("size", _("Size"), 60).range (2, 10000).ui_range (5, 400));
                g.add<Property> (Factory.point ("offset", _("Offset"), { 0, 0 }));
                g.add<Property> (Factory.angle ("evolution", _("Evolution"), 0));
                g.add<Property> (Factory.scalar ("seed", _("Random Seed"), 0).range (0, 100000));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("blend", _("Blending Mode"), blend_labels (), 0));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                int pattern = fx.choice ("pattern", t);
                bool inv = fx.toggle ("invert", t);
                double contrast = fx.num ("contrast", t) / 100.0;
                double disperse = fx.num ("disperse", t);
                double size = ctx.px (double.max (2, fx.num ("size", t)));
                var off = fx.vec ("offset", t);
                double evo = fx.num ("evolution", t) / 360.0 * 2 * Math.PI;
                int seed = (int) fx.num ("seed", t);
                Parallel.range (img.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < img.width; x++) {
                            double u = (x + 0.5 + ctx.px (off[0])) / size, v = (y + 0.5 + ctx.px (off[1])) / size;
                            int ix = (int) Math.floor (u), iy = (int) Math.floor (v);
                            double f1 = 1e9, f2 = 1e9;
                            int best_x = 0, best_y = 0;
                            for (int j = -1; j <= 1; j++)
                                for (int i = -1; i <= 1; i++) {
                                    int cx = ix + i, cy = iy + j;
                                    double ph = Noise.hash01 (cx, cy, seed + 5) * 2 * Math.PI;
                                    double jx = 0.5 + (Noise.hash01 (cx, cy, seed) - 0.5) * disperse + Math.cos (evo + ph) * 0.15 * disperse;
                                    double jy = 0.5 + (Noise.hash01 (cx, cy, seed + 1) - 0.5) * disperse + Math.sin (evo + ph) * 0.15 * disperse;
                                    double d = Math.hypot (cx + jx - u, cy + jy - v);
                                    if (d < f1) {
                                        f2 = f1;
                                        f1 = d;
                                        best_x = cx;
                                        best_y = cy;
                                    } else if (d < f2) {
                                        f2 = d;
                                    }
                                }
                            double val;
                            switch (pattern) {
                                case 1: val = ((f2 - f1) * 2).clamp (0, 1); break;
                                case 2: val = Noise.hash01 (best_x, best_y, seed + 9) * smoothstep (0.0, 0.06, f2 - f1); break;
                                case 3: val = Noise.hash01 (best_x, best_y, seed + 9); break;
                                case 4: val = ((f2 - f1) * 2).clamp (0, 1) * 0.5 + Noise.hash01 (best_x, best_y, seed + 9) * 0.5; break;
                                case 5: val = Math.sin ((f2 - f1) * Math.PI * 4).abs (); break;
                                default: val = (1 - f1 * 1.4).clamp (0, 1); break;
                            }
                            val = ((val - 0.5) * contrast + 0.5).clamp (0, 1);
                            if (inv) val = 1 - val;
                            float lin = Transfer.srgb_to_linear ((float) val);
                            set_premul (gen, (size_t) y * img.width + x, lin, lin, lin, 1);
                        }
                });
                compose (ctx, gen, fx.num ("opacity", t) / 100.0, fx.choice ("blend", t));
            }));

            EffectRegistry.add (new EffectDef ("checkerboard", _("Checkerboard"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("anchor", _("Anchor"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("width", _("Width"), 64).range (1, 10000).ui_range (2, 500));
                g.add<Property> (Factory.scalar ("height", _("Height"), 64).range (1, 10000).ui_range (2, 500));
                g.add<Property> (Factory.color ("color", _("Color"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("blend", _("Blending Mode"), blend_labels (), 0));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                var anc = FxUtil.point_in_pixels (ctx, fx, "anchor");
                double cw = ctx.px (double.max (1, fx.num ("width", t))), ch = ctx.px (double.max (1, fx.num ("height", t)));
                var col = fx.vec ("color", t);
                for (int y = 0; y < img.height; y++)
                    for (int x = 0; x < img.width; x++) {
                        int cx = (int) Math.floor ((x + 0.5 - anc[0]) / cw), cy = (int) Math.floor ((y + 0.5 - anc[1]) / ch);
                        bool on = ((cx + cy) & 1) == 0;
                        set_premul (gen, (size_t) y * img.width + x, col[0], col[1], col[2], on ? col[3] : 0);
                    }
                compose (ctx, gen, fx.num ("opacity", t) / 100.0, fx.choice ("blend", t));
            }));

            EffectRegistry.add (new EffectDef ("circle", _("Circle"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("center", _("Center"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("radius", _("Radius"), 75).range (0, 10000).ui_range (0, 1000));
                g.add<Property> (Factory.choice ("edge", _("Edge"), { _("None"), _("Thickness") }));
                g.add<Property> (Factory.scalar ("thickness", _("Thickness"), 10).range (0, 10000).ui_range (0, 200));
                g.add<Property> (Factory.scalar ("feather-outer", _("Feather Outer Edge"), 0).range (0, 1000).ui_range (0, 100));
                g.add<Property> (Factory.scalar ("feather-inner", _("Feather Inner Edge"), 0).range (0, 1000).ui_range (0, 100));
                g.add<Property> (Factory.toggle ("invert", _("Invert Circle"), false));
                g.add<Property> (Factory.color ("color", _("Color"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("blend", _("Blending Mode"), blend_labels (), 1));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double r = ctx.px (fx.num ("radius", t));
                bool ring = fx.choice ("edge", t) == 1;
                double th = ctx.px (fx.num ("thickness", t));
                double fo = ctx.px (fx.num ("feather-outer", t)), fi = ctx.px (fx.num ("feather-inner", t));
                bool inv = fx.toggle ("invert", t);
                var col = fx.vec ("color", t);
                for (int y = 0; y < img.height; y++)
                    for (int x = 0; x < img.width; x++) {
                        double d = Math.hypot (x + 0.5 - c[0], y + 0.5 - c[1]);
                        double a = 1 - smoothstep (r - fo / 2 - 0.5, r + fo / 2 + 0.5, d);
                        if (ring) a *= smoothstep (r - th - fi / 2 - 0.5, r - th + fi / 2 + 0.5, d);
                        if (inv) a = 1 - a;
                        set_premul (gen, (size_t) y * img.width + x, col[0], col[1], col[2], a * col[3]);
                    }
                compose (ctx, gen, fx.num ("opacity", t) / 100.0, fx.choice ("blend", t));
            }));

            EffectRegistry.add (new EffectDef ("ellipse", _("Ellipse"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("center", _("Center"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("width", _("Width"), 200).range (0, 10000).ui_range (0, 1000));
                g.add<Property> (Factory.scalar ("height", _("Height"), 120).range (0, 10000).ui_range (0, 1000));
                g.add<Property> (Factory.scalar ("thickness", _("Thickness"), 8).range (0, 1000).ui_range (0, 100));
                g.add<Property> (Factory.percent ("softness", _("Softness"), 20).range (0, 100));
                g.add<Property> (Factory.color ("inside", _("Inside Color"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.color ("outside", _("Outside Color"), { 0.2, 0.5, 1, 1 }));
                g.add<Property> (Factory.toggle ("composite", _("Composite On Original"), true));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double rx = double.max (0.5, ctx.px (fx.num ("width", t)) / 2), ry = double.max (0.5, ctx.px (fx.num ("height", t)) / 2);
                double th = double.max (0.5, ctx.px (fx.num ("thickness", t)));
                double soft = fx.num ("softness", t) / 100.0;
                var ic = fx.vec ("inside", t);
                var oc = fx.vec ("outside", t);
                for (int y = 0; y < img.height; y++)
                    for (int x = 0; x < img.width; x++) {
                        double u = (x + 0.5 - c[0]) / rx, v = (y + 0.5 - c[1]) / ry;
                        double d = (Math.sqrt (u * u + v * v) - 1) * double.min (rx, ry);
                        double dist = d.abs ();
                        double half = th / 2;
                        double core = 1 - smoothstep (half * (1 - soft) - 0.5, half + 0.5, dist);
                        double glow = (1 - smoothstep (half, half + th * (0.5 + soft * 2), dist)) * 0.8;
                        double a = double.max (core, glow);
                        double r = oc[0] + (ic[0] - oc[0]) * core, g2 = oc[1] + (ic[1] - oc[1]) * core, b = oc[2] + (ic[2] - oc[2]) * core;
                        set_premul (gen, (size_t) y * img.width + x, r, g2, b, a);
                    }
                if (fx.toggle ("composite", t)) Pixels.blend (img, new CompImage (gen, 0, 0), BlendMode.NORMAL, true, false);
                else ctx.buf.img = gen;
            }));

            EffectRegistry.add (new EffectDef ("four-color-gradient", _("4-Color Gradient"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("point1", _("Point 1"), { 0, 0 }));
                g.add<Property> (Factory.color ("color1", _("Color 1"), { 1, 1, 0, 1 }));
                g.add<Property> (Factory.point ("point2", _("Point 2"), { 400, 0 }));
                g.add<Property> (Factory.color ("color2", _("Color 2"), { 0, 1, 0, 1 }));
                g.add<Property> (Factory.point ("point3", _("Point 3"), { 0, 300 }));
                g.add<Property> (Factory.color ("color3", _("Color 3"), { 1, 0, 1, 1 }));
                g.add<Property> (Factory.point ("point4", _("Point 4"), { 400, 300 }));
                g.add<Property> (Factory.color ("color4", _("Color 4"), { 0, 0, 1, 1 }));
                g.add<Property> (Factory.scalar ("blend-amount", _("Blend"), 100).range (1, 1000).ui_range (1, 400));
                g.add<Property> (Factory.scalar ("jitter", _("Jitter"), 0).range (0, 100));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("blend", _("Blending Mode"), blend_labels (), 0));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var gen = new FloatImage (img.width, img.height);
                double[,] pts = new double[4, 2];
                double[,] cols = new double[4, 3];
                for (int k = 0; k < 4; k++) {
                    var p = FxUtil.point_in_pixels (ctx, fx, "point%d".printf (k + 1));
                    var cv = fx.vec ("color%d".printf (k + 1), t);
                    pts[k, 0] = p[0];
                    pts[k, 1] = p[1];
                    for (int ch = 0; ch < 3; ch++) cols[k, ch] = cv[ch];
                }
                double power = 1 + fx.num ("blend-amount", t) / 50.0;
                double jitter = fx.num ("jitter", t) / 100.0;
                for (int y = 0; y < img.height; y++)
                    for (int x = 0; x < img.width; x++) {
                        double wsum = 0, r = 0, g2 = 0, b = 0;
                        for (int k = 0; k < 4; k++) {
                            double d = Math.hypot (x + 0.5 - pts[k, 0], y + 0.5 - pts[k, 1]);
                            double w = 1.0 / Math.pow (double.max (1e-3, d), power);
                            wsum += w;
                            r += cols[k, 0] * w;
                            g2 += cols[k, 1] * w;
                            b += cols[k, 2] * w;
                        }
                        double jt = jitter > 0 ? (Noise.hash01 (x, y, 77) - 0.5) * jitter * 0.1 : 0;
                        set_premul (gen, (size_t) y * img.width + x, r / wsum + jt, g2 / wsum + jt, b / wsum + jt, 1);
                    }
                compose (ctx, gen, fx.num ("opacity", t) / 100.0, fx.choice ("blend", t));
            }));
        }

        private void bolt (Cairo.Context cr, double x0, double y0, double x1, double y1, int depth, double amp, double branch, double rebranch, double evo, int seed, double width_k, double core, ref int counter) {
            Singularity.Vector.Point[] pts = { Singularity.Vector.Point (x0, y0), Singularity.Vector.Point (x1, y1) };
            double len = Math.hypot (x1 - x0, y1 - y0);
            double disp = len * amp;
            for (int level = 0; level < depth; level++) {
                Singularity.Vector.Point[] next = {};
                for (int i = 0; i < pts.length - 1; i++) {
                    var a = pts[i];
                    var b = pts[i + 1];
                    double mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
                    double dx = b.x - a.x, dy = b.y - a.y;
                    double l = Math.hypot (dx, dy);
                    double nx = l > 0 ? -dy / l : 0, ny = l > 0 ? dx / l : 0;
                    double n = Noise.perlin2 (i * 1.37 + level * 11.1, evo * 3, seed + counter);
                    next += a;
                    next += Singularity.Vector.Point (mx + nx * n * disp, my + ny * n * disp);
                }
                next += pts[pts.length - 1];
                pts = next;
                disp *= 0.55;
            }
            cr.set_line_width (core * width_k);
            cr.move_to (pts[0].x, pts[0].y);
            for (int i = 1; i < pts.length; i++) cr.line_to (pts[i].x, pts[i].y);
            cr.stroke ();
            counter++;
            if (width_k < 0.2 || counter > 64) return;
            for (int i = 1; i < pts.length - 1; i++) {
                if (Noise.hash01 (i, seed + counter, 313) >= branch * 0.25) continue;
                double ang = Math.atan2 (y1 - y0, x1 - x0) + (Noise.hash01 (i, seed, 7) - 0.5) * 1.6;
                double bl = len * (0.2 + Noise.hash01 (i, seed, 9) * 0.3);
                bolt (cr, pts[i].x, pts[i].y, pts[i].x + Math.cos (ang) * bl, pts[i].y + Math.sin (ang) * bl, int.max (1, depth - 2), amp, rebranch, rebranch * 0.5, evo, seed + i * 7, width_k * 0.5, core, ref counter);
            }
        }
    }
}
