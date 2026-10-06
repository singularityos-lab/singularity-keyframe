using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace EffectsBasic {
        public void register () {
            EffectRegistry.add (new EffectDef ("gaussian-blur", _("Gaussian Blur"), _("Blur & Sharpen"), (g) => {
                g.add<Property> (Factory.scalar ("blurriness", _("Blurriness"), 10).range (0, 3000).ui_range (0, 200));
                g.add<Property> (Factory.choice ("dimensions", _("Blur Dimensions"), { _("Horizontal and Vertical"), _("Horizontal"), _("Vertical") }));
                g.add<Property> (Factory.toggle ("repeat-edges", _("Repeat Edge Pixels"), false));
            }, (ctx, fx, t) => {
                double b = ctx.px (fx.num ("blurriness", t)) / 2.0;
                int dim = fx.choice ("dimensions", t);
                if (fx.toggle ("repeat-edges", t)) repeat_edges_blur (ctx.buf.img, dim == 2 ? 0 : b, dim == 1 ? 0 : b);
                else Blur.gaussian (ctx.buf.img, dim == 2 ? 0 : b, dim == 1 ? 0 : b);
            }, (fx, t) => fx.toggle ("repeat-edges", t) ? 0 : fx.num ("blurriness", t) * 1.6));

            EffectRegistry.add (new EffectDef ("directional-blur", _("Directional Blur"), _("Blur & Sharpen"), (g) => {
                g.add<Property> (Factory.angle ("direction", _("Direction"), 0));
                g.add<Property> (Factory.scalar ("length", _("Blur Length"), 10).range (0, 1000).ui_range (0, 200));
            }, (ctx, fx, t) => {
                Blur.directional (ctx.buf.img, fx.num ("direction", t), ctx.px (fx.num ("length", t)));
            }, (fx, t) => fx.num ("length", t)));

            EffectRegistry.add (new EffectDef ("radial-blur", _("Radial Blur"), _("Blur & Sharpen"), (g) => {
                g.add<Property> (Factory.scalar ("amount", _("Amount"), 10).range (0, 360).ui_range (0, 100));
                g.add<Property> (Factory.point ("center", _("Center"), { 0, 0 }));
                g.add<Property> (Factory.choice ("type", _("Type"), { _("Spin"), _("Zoom") }));
            }, (ctx, fx, t) => {
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                Blur.radial (ctx.buf.img, c[0], c[1], fx.num ("amount", t), fx.choice ("type", t) == 1);
            }));

            EffectRegistry.add (new EffectDef ("sharpen", _("Sharpen"), _("Blur & Sharpen"), (g) => {
                g.add<Property> (Factory.scalar ("amount", _("Sharpen Amount"), 20).range (0, 500).ui_range (0, 100));
                g.add<Property> (Factory.scalar ("radius", _("Radius"), 1.5).range (0.1, 50).ui_range (0.1, 10));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var blurred = img.copy ();
                Blur.gaussian (blurred, ctx.px (fx.num ("radius", t)), ctx.px (fx.num ("radius", t)));
                float k = (float) (fx.num ("amount", t) / 100.0);
                size_t n = img.pixel_count ();
                for (size_t i = 0; i < n; i++)
                    for (int c = 0; c < 3; c++) img.data[i * 4 + c] = float.max (0, img.data[i * 4 + c] + (img.data[i * 4 + c] - blurred.data[i * 4 + c]) * k);
            }));

            EffectRegistry.add (new EffectDef ("glow", _("Glow"), _("Stylize"), (g) => {
                g.add<Property> (Factory.percent ("threshold", _("Glow Threshold"), 60).range (0, 100));
                g.add<Property> (Factory.scalar ("radius", _("Glow Radius"), 10).range (0, 1000).ui_range (0, 200));
                g.add<Property> (Factory.scalar ("intensity", _("Glow Intensity"), 1).range (0, 255).ui_range (0, 4));
                g.add<Property> (Factory.choice ("colors", _("Glow Colors"), { _("Original Colors"), _("A & B Colors") }));
                g.add<Property> (Factory.color ("color-a", _("Color A"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.color ("color-b", _("Color B"), { 0, 0, 0, 1 }));
                g.add<Property> (Factory.choice ("operation", _("Glow Operation"), { _("Add"), _("Screen") }));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                float th = (float) (fx.num ("threshold", t) / 100.0);
                var bright = new FloatImage (img.width, img.height);
                bool ab = fx.choice ("colors", t) == 1;
                var ca = fx.vec ("color-a", t);
                var cb = fx.vec ("color-b", t);
                size_t n = img.pixel_count ();
                for (size_t i = 0; i < n; i++) {
                    float a = img.data[i * 4 + 3];
                    if (a <= 0) continue;
                    float r = img.data[i * 4] / a, g = img.data[i * 4 + 1] / a, b = img.data[i * 4 + 2] / a;
                    float l = Transfer.linear_to_srgb (Pixels.luma (r, g, b).clamp (0, 1));
                    float k = th >= 1 ? 0 : ((l - th) / (1 - th)).clamp (0, 1);
                    if (k <= 0) continue;
                    if (ab) {
                        r = (float) (cb[0] + (ca[0] - cb[0]) * l);
                        g = (float) (cb[1] + (ca[1] - cb[1]) * l);
                        b = (float) (cb[2] + (ca[2] - cb[2]) * l);
                    }
                    bright.data[i * 4] = r * k * a;
                    bright.data[i * 4 + 1] = g * k * a;
                    bright.data[i * 4 + 2] = b * k * a;
                    bright.data[i * 4 + 3] = k * a;
                }
                double s = ctx.px (fx.num ("radius", t)) / 2.0;
                Blur.gaussian (bright, s, s);
                float inten = (float) fx.num ("intensity", t);
                bool screen = fx.choice ("operation", t) == 1;
                for (size_t i = 0; i < n; i++) {
                    for (int c = 0; c < 3; c++) {
                        float add = bright.data[i * 4 + c] * inten;
                        float base_v = img.data[i * 4 + c];
                        img.data[i * 4 + c] = screen ? base_v + add - base_v * add.clamp (0, 1) : base_v + add;
                    }
                    float ga = (bright.data[i * 4 + 3] * inten).clamp (0, 1);
                    img.data[i * 4 + 3] = img.data[i * 4 + 3] + ga - img.data[i * 4 + 3] * ga;
                }
            }, (fx, t) => fx.num ("radius", t) * 1.6));

            EffectRegistry.add (new EffectDef ("drop-shadow", _("Drop Shadow"), _("Perspective"), (g) => {
                g.add<Property> (Factory.color ("color", _("Shadow Color"), { 0, 0, 0, 1 }));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 50).range (0, 100));
                g.add<Property> (Factory.angle ("direction", _("Direction"), 135));
                g.add<Property> (Factory.scalar ("distance", _("Distance"), 5).range (0, 32000).ui_range (0, 200));
                g.add<Property> (Factory.scalar ("softness", _("Softness"), 0).range (0, 1000).ui_range (0, 200));
                g.add<Property> (Factory.toggle ("shadow-only", _("Shadow Only"), false));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var col = fx.vec ("color", t);
                float op = (float) (fx.num ("opacity", t) / 100.0);
                double ang = (fx.num ("direction", t) - 90) * Math.PI / 180.0;
                double dist = ctx.px (fx.num ("distance", t));
                int dx = (int) Math.round (Math.cos (ang) * dist), dy = (int) Math.round (Math.sin (ang) * dist);
                var shadow = new FloatImage (img.width, img.height);
                for (int y = 0; y < img.height; y++)
                    for (int x = 0; x < img.width; x++) {
                        int sx = x - dx, sy = y - dy;
                        if (sx < 0 || sy < 0 || sx >= img.width || sy >= img.height) continue;
                        float a = img.data[img.offset (sx, sy) + 3] * op;
                        size_t o = shadow.offset (x, y);
                        shadow.data[o] = (float) col[0] * a;
                        shadow.data[o + 1] = (float) col[1] * a;
                        shadow.data[o + 2] = (float) col[2] * a;
                        shadow.data[o + 3] = a;
                    }
                double soft = ctx.px (fx.num ("softness", t)) / 2.0;
                if (soft > 0) Blur.gaussian (shadow, soft, soft);
                if (!fx.toggle ("shadow-only", t)) Pixels.blend (shadow, new CompImage (img, 0, 0), BlendMode.NORMAL, true, false);
                ctx.buf.img = shadow;
            }, (fx, t) => fx.num ("distance", t) + fx.num ("softness", t) * 1.6));

            EffectRegistry.add (new EffectDef ("fill", _("Fill"), _("Generate"), (g) => {
                g.add<Property> (Factory.color ("color", _("Color"), { 1, 0, 0, 1 }));
                g.add<Property> (Factory.toggle ("invert", _("Invert"), false));
                g.add<Property> (Factory.scalar ("feather", _("Horizontal Feather"), 0).range (0, 1000));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var col = fx.vec ("color", t);
                float op = (float) (fx.num ("opacity", t) / 100.0);
                bool inv = fx.toggle ("invert", t);
                size_t n = img.pixel_count ();
                for (size_t i = 0; i < n; i++) {
                    float a = img.data[i * 4 + 3];
                    float cover = inv ? 1 - a : a;
                    float r = (float) col[0] * cover, g = (float) col[1] * cover, b = (float) col[2] * cover;
                    img.data[i * 4] = img.data[i * 4] + (r - img.data[i * 4]) * op;
                    img.data[i * 4 + 1] = img.data[i * 4 + 1] + (g - img.data[i * 4 + 1]) * op;
                    img.data[i * 4 + 2] = img.data[i * 4 + 2] + (b - img.data[i * 4 + 2]) * op;
                    if (inv) img.data[i * 4 + 3] = a + (cover - a) * op;
                }
            }));

            EffectRegistry.add (new EffectDef ("gradient-ramp", _("Gradient Ramp"), _("Generate"), (g) => {
                g.add<Property> (Factory.point ("start", _("Start of Ramp"), { 0, 0 }));
                g.add<Property> (Factory.color ("start-color", _("Start Color"), { 0, 0, 0, 1 }));
                g.add<Property> (Factory.point ("end", _("End of Ramp"), { 0, 500 }));
                g.add<Property> (Factory.color ("end-color", _("End Color"), { 1, 1, 1, 1 }));
                g.add<Property> (Factory.choice ("shape", _("Ramp Shape"), { _("Linear Ramp"), _("Radial Ramp") }));
                g.add<Property> (Factory.scalar ("scatter", _("Ramp Scatter"), 0).range (0, 1000).ui_range (0, 100));
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var orig = img.copy ();
                var gs = new GradientSpec ();
                gs.radial = fx.choice ("shape", t) == 1;
                var sp = FxUtil.point_in_pixels (ctx, fx, "start");
                var ep = FxUtil.point_in_pixels (ctx, fx, "end");
                gs.sx = sp[0];
                gs.sy = sp[1];
                gs.ex = ep[0];
                gs.ey = ep[1];
                var c0 = fx.vec ("start-color", t);
                var c1 = fx.vec ("end-color", t);
                gs.stops = { 0, c0[0], c0[1], c0[2], 1, 1, c1[0], c1[1], c1[2], 1 };
                double scatter = fx.num ("scatter", t) / 1000.0;
                Parallel.range (img.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < img.width; x++) {
                            size_t o = img.offset (x, y);
                            float a = img.data[o + 3];
                            double p = gs.param_at (x + 0.5, y + 0.5);
                            if (scatter > 0) p += (Noise.hash01 (x, y, 3) - 0.5) * scatter;
                            float r, g, b, ga;
                            gs.color_at (p, out r, out g, out b, out ga);
                            img.data[o] = r * a;
                            img.data[o + 1] = g * a;
                            img.data[o + 2] = b * a;
                        }
                });
                FxUtil.mix_original (img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("invert", _("Invert"), _("Channel"), (g) => {
                g.add<Property> (Factory.choice ("channel", _("Channel"), { _("RGB"), _("Red"), _("Green"), _("Blue"), _("Alpha"), _("Luminance") }));
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var orig = img.copy ();
                int ch = fx.choice ("channel", t);
                if (ch == 4) {
                    size_t n = img.pixel_count ();
                    for (size_t i = 0; i < n; i++) {
                        float a = img.data[i * 4 + 3];
                        float na = 1 - a;
                        float k = a > 1e-6f ? na / a : 0;
                        for (int c = 0; c < 3; c++) img.data[i * 4 + c] *= k;
                        img.data[i * 4 + 3] = na;
                    }
                } else {
                    FxUtil.per_pixel (img, (ref r, ref g, ref b, ref a) => {
                        float er = Transfer.linear_to_srgb (r.clamp (0, 1)), eg = Transfer.linear_to_srgb (g.clamp (0, 1)), eb = Transfer.linear_to_srgb (b.clamp (0, 1));
                        switch (ch) {
                            case 1: er = 1 - er; break;
                            case 2: eg = 1 - eg; break;
                            case 3: eb = 1 - eb; break;
                            case 5:
                                float l = 0.299f * er + 0.587f * eg + 0.114f * eb;
                                float d = (1 - l) - l;
                                er += d;
                                eg += d;
                                eb += d;
                                break;
                            default:
                                er = 1 - er;
                                eg = 1 - eg;
                                eb = 1 - eb;
                                break;
                        }
                        r = Transfer.srgb_to_linear (er.clamp (0, 1));
                        g = Transfer.srgb_to_linear (eg.clamp (0, 1));
                        b = Transfer.srgb_to_linear (eb.clamp (0, 1));
                    });
                }
                FxUtil.mix_original (img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("mosaic", _("Mosaic"), _("Stylize"), (g) => {
                g.add<Property> (Factory.scalar ("horizontal", _("Horizontal Blocks"), 10).range (1, 4000).ui_range (1, 200));
                g.add<Property> (Factory.scalar ("vertical", _("Vertical Blocks"), 10).range (1, 4000).ui_range (1, 200));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                int bx = int.max (1, (int) fx.num ("horizontal", t)), by = int.max (1, (int) fx.num ("vertical", t));
                double cw = (double) img.width / bx, ch = (double) img.height / by;
                for (int j = 0; j < by; j++)
                    for (int i = 0; i < bx; i++) {
                        int x0 = (int) (i * cw), x1 = int.min (img.width, (int) ((i + 1) * cw));
                        int y0 = (int) (j * ch), y1 = int.min (img.height, (int) ((j + 1) * ch));
                        float r = 0, g = 0, b = 0, a = 0;
                        int cnt = 0;
                        for (int y = y0; y < y1; y++)
                            for (int x = x0; x < x1; x++) {
                                size_t o = img.offset (x, y);
                                r += img.data[o];
                                g += img.data[o + 1];
                                b += img.data[o + 2];
                                a += img.data[o + 3];
                                cnt++;
                            }
                        if (cnt == 0) continue;
                        for (int y = y0; y < y1; y++)
                            for (int x = x0; x < x1; x++) {
                                size_t o = img.offset (x, y);
                                img.data[o] = r / cnt;
                                img.data[o + 1] = g / cnt;
                                img.data[o + 2] = b / cnt;
                                img.data[o + 3] = a / cnt;
                            }
                    }
            }));

            EffectRegistry.add (new EffectDef ("posterize", _("Posterize"), _("Stylize"), (g) => {
                g.add<Property> (Factory.scalar ("level", _("Level"), 6).range (2, 255).ui_range (2, 32));
            }, (ctx, fx, t) => {
                float lv = (float) fx.num ("level", t) - 1;
                FxUtil.per_pixel (ctx.buf.img, (ref r, ref g, ref b, ref a) => {
                    r = Transfer.srgb_to_linear (Math.roundf (Transfer.linear_to_srgb (r.clamp (0, 1)) * lv) / lv);
                    g = Transfer.srgb_to_linear (Math.roundf (Transfer.linear_to_srgb (g.clamp (0, 1)) * lv) / lv);
                    b = Transfer.srgb_to_linear (Math.roundf (Transfer.linear_to_srgb (b.clamp (0, 1)) * lv) / lv);
                });
            }));

            EffectRegistry.add (new EffectDef ("find-edges", _("Find Edges"), _("Stylize"), (g) => {
                g.add<Property> (Factory.toggle ("invert", _("Invert"), false));
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                var orig = img.copy ();
                var lum = new float[img.pixel_count ()];
                for (size_t i = 0; i < lum.length; i++) lum[i] = Transfer.linear_to_srgb (Pixels.luma (orig.data[i * 4], orig.data[i * 4 + 1], orig.data[i * 4 + 2]).clamp (0, 1));
                bool inv = fx.toggle ("invert", t);
                for (int y = 0; y < img.height; y++)
                    for (int x = 0; x < img.width; x++) {
                        float gx = lum[(size_t) y * img.width + int.min (x + 1, img.width - 1)] - lum[(size_t) y * img.width + int.max (x - 1, 0)];
                        float gy = lum[(size_t) int.min (y + 1, img.height - 1) * img.width + x] - lum[(size_t) int.max (y - 1, 0) * img.width + x];
                        float e = float.min (1, Math.sqrtf (gx * gx + gy * gy) * 2);
                        float v = inv ? e : 1 - e;
                        float lin = Transfer.srgb_to_linear (v);
                        size_t o = img.offset (x, y);
                        float a = orig.data[o + 3];
                        img.data[o] = lin * a;
                        img.data[o + 1] = lin * a;
                        img.data[o + 2] = lin * a;
                    }
                FxUtil.mix_original (img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("noise", _("Noise"), _("Noise & Grain"), (g) => {
                g.add<Property> (Factory.percent ("amount", _("Amount of Noise"), 10).range (0, 100));
                g.add<Property> (Factory.toggle ("color", _("Use Color Noise"), true));
                g.add<Property> (Factory.toggle ("animated", _("Animated"), true));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                float amt = (float) (fx.num ("amount", t) / 100.0);
                bool colour = fx.toggle ("color", t);
                int frame = fx.toggle ("animated", t) ? (int) (ctx.comp_time * ctx.comp.fps) : 0;
                Parallel.range (img.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < img.width; x++) {
                            size_t o = img.offset (x, y);
                            float a = img.data[o + 3];
                            if (a <= 0) continue;
                            for (int c = 0; c < 3; c++) {
                                float n = (float) (Noise.hash01 (x, y * 3 + (colour ? c : 0), frame * 7 + 1) - 0.5) * amt;
                                float v = Transfer.linear_to_srgb ((img.data[o + c] / a).clamp (0, 1)) + n;
                                img.data[o + c] = Transfer.srgb_to_linear (v.clamp (0, 1)) * a;
                            }
                        }
                });
            }));

            EffectRegistry.add (new EffectDef ("transform", _("Transform"), _("Distort"), (g) => {
                g.add<Property> (Factory.point ("anchor", _("Anchor Point"), { 0, 0 }));
                g.add<Property> (Factory.point ("position", _("Position"), { 0, 0 }));
                g.add<Property> (Factory.vec ("scale", _("Scale"), { 100, 100 }));
                g.add<Property> (Factory.scalar ("skew", _("Skew"), 0).range (-85, 85));
                g.add<Property> (Factory.angle ("skew-axis", _("Skew Axis"), 0));
                g.add<Property> (Factory.angle ("rotation", _("Rotation"), 0));
                g.add<Property> (Factory.percent ("opacity", _("Opacity"), 100).range (0, 100));
            }, (ctx, fx, t) => {
                var m = ShapeRenderer.group_matrix (fx, t);
                var to_px = Mat4.scaling (ctx.buf.scale, ctx.buf.scale, 1).multiply (Mat4.translation (-ctx.buf.x0, -ctx.buf.y0, 0));
                var full = to_px.multiply (m).multiply (ctx.buf.pixel_to_layer ());
                var inv = full.inverted ();
                if (inv == null) return;
                var src = ctx.buf.img;
                var dst = new FloatImage (src.width, src.height);
                float op = (float) (fx.num ("opacity", t) / 100.0);
                Parallel.range (dst.height, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < dst.width; x++) {
                            var p = inv.transform_point (Vec3 (x + 0.5, y + 0.5, 0));
                            float r, g, b, a;
                            Pixels.sample_premul (src, p.x, p.y, out r, out g, out b, out a);
                            size_t o = dst.offset (x, y);
                            dst.data[o] = r * op;
                            dst.data[o + 1] = g * op;
                            dst.data[o + 2] = b * op;
                            dst.data[o + 3] = a * op;
                        }
                });
                ctx.buf.img = dst;
            }));

            EffectRegistry.add (new EffectDef ("corner-pin", _("Corner Pin"), _("Distort"), (g) => {
                g.add<Property> (Factory.point ("upper-left", _("Upper Left"), { 0, 0 }));
                g.add<Property> (Factory.point ("upper-right", _("Upper Right"), { 1920, 0 }));
                g.add<Property> (Factory.point ("lower-left", _("Lower Left"), { 0, 1080 }));
                g.add<Property> (Factory.point ("lower-right", _("Lower Right"), { 1920, 1080 }));
            }, (ctx, fx, t) => {
                var src = ctx.buf.img;
                double w = ctx.buf.width_units (), h = ctx.buf.height_units ();
                double[] from = { ctx.buf.x0, ctx.buf.y0, ctx.buf.x0 + w, ctx.buf.y0, ctx.buf.x0, ctx.buf.y0 + h, ctx.buf.x0 + w, ctx.buf.y0 + h };
                var ul = fx.vec ("upper-left", t);
                var ur = fx.vec ("upper-right", t);
                var ll = fx.vec ("lower-left", t);
                var lr = fx.vec ("lower-right", t);
                double[] to = { ul[0], ul[1], ur[0], ur[1], ll[0], ll[1], lr[0], lr[1] };
                double[] src_q = { from[0], from[1], from[2], from[3], from[6], from[7], from[4], from[5] };
                double[] dst_q = { to[0], to[1], to[2], to[3], to[6], to[7], to[4], to[5] };
                var hm = Homography.from_quads (dst_q, src_q);
                if (hm == null) return;
                double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
                for (int i = 0; i < 4; i++) {
                    minx = double.min (minx, to[i * 2]);
                    maxx = double.max (maxx, to[i * 2]);
                    miny = double.min (miny, to[i * 2 + 1]);
                    maxy = double.max (maxy, to[i * 2 + 1]);
                }
                minx = double.min (minx, ctx.buf.x0);
                miny = double.min (miny, ctx.buf.y0);
                maxx = double.max (maxx, ctx.buf.x0 + w);
                maxy = double.max (maxy, ctx.buf.y0 + h);
                double sc = ctx.buf.scale;
                int nw = int.min (8192, (int) Math.ceil ((maxx - minx) * sc)), nh = int.min (8192, (int) Math.ceil ((maxy - miny) * sc));
                var dst = new FloatImage (nw, nh);
                Parallel.range (nh, (s, e) => {
                    for (int y = s; y < e; y++)
                        for (int x = 0; x < nw; x++) {
                            double lx = minx + (x + 0.5) / sc, ly = miny + (y + 0.5) / sc;
                            double ux, uy;
                            hm.apply (lx, ly, out ux, out uy);
                            float r, g, b, a;
                            Pixels.sample_premul (src, (ux - ctx.buf.x0) * sc, (uy - ctx.buf.y0) * sc, out r, out g, out b, out a);
                            size_t o = dst.offset (x, y);
                            dst.data[o] = r;
                            dst.data[o + 1] = g;
                            dst.data[o + 2] = b;
                            dst.data[o + 3] = a;
                        }
                });
                ctx.buf = new LayerBuffer (dst, minx, miny, sc);
            }));

            EffectRegistry.add (new EffectDef ("set-matte", _("Set Matte"), _("Channel"), (g) => {
                g.add<Property> (Factory.layer_ref ("layer", _("Take Matte From Layer")));
                g.add<Property> (Factory.choice ("channel", _("Use For Matte"), { _("Alpha Channel"), _("Luminance"), _("Red"), _("Green"), _("Blue") }));
                g.add<Property> (Factory.toggle ("invert", _("Invert Matte"), false));
                g.add<Property> (Factory.toggle ("premultiply", _("Premultiply Matte Layer"), true));
            }, (ctx, fx, t) => {
                var other = ctx.layer_param (fx, "layer");
                if (other == null) return;
                var m = ctx.other_layer_in_buffer (other);
                int ch = fx.choice ("channel", t);
                bool inv = fx.toggle ("invert", t);
                var img = ctx.buf.img;
                size_t n = img.pixel_count ();
                for (size_t i = 0; i < n; i++) {
                    float a = m.data[i * 4 + 3];
                    float v;
                    switch (ch) {
                        case 1: v = a > 0 ? Pixels.luma (m.data[i * 4], m.data[i * 4 + 1], m.data[i * 4 + 2]).clamp (0, 1) : 0; break;
                        case 2: v = m.data[i * 4]; break;
                        case 3: v = m.data[i * 4 + 1]; break;
                        case 4: v = m.data[i * 4 + 2]; break;
                        default: v = a; break;
                    }
                    if (inv) v = 1 - v;
                    for (int c = 0; c < 4; c++) img.data[i * 4 + c] *= v.clamp (0, 1);
                }
            }));

            EffectRegistry.add (new EffectDef ("simple-choker", _("Simple Choker"), _("Matte"), (g) => {
                g.add<Property> (Factory.scalar ("choke", _("Choke Matte"), 0).range (-100, 100).ui_range (-20, 20));
            }, (ctx, fx, t) => {
                var img = ctx.buf.img;
                double choke = ctx.px (fx.num ("choke", t));
                if (choke.abs () < 0.01) return;
                var mask = new float[img.pixel_count ()];
                for (size_t i = 0; i < mask.length; i++) mask[i] = img.data[i * 4 + 3];
                var sd = DistanceField.signed_distance (mask, img.width, img.height);
                for (size_t i = 0; i < mask.length; i++) {
                    float a = img.data[i * 4 + 3];
                    float na = ((float) (sd[i] - choke) + 0.5f).clamp (0, 1);
                    if (choke < 0) na = float.max (a, na);
                    else na = float.min (a, na);
                    float k = a > 1e-6f ? na / a : 0;
                    for (int c = 0; c < 3; c++) img.data[i * 4 + c] *= k;
                    img.data[i * 4 + 3] = na;
                }
            }, (fx, t) => double.max (0, -fx.num ("choke", t))));
        }

        public void repeat_edges_blur (FloatImage img, double sx, double sy) {
            int pad = (int) Math.ceil (double.max (sx, sy) * 3) + 1;
            var big = new FloatImage (img.width + pad * 2, img.height + pad * 2);
            for (int y = 0; y < big.height; y++)
                for (int x = 0; x < big.width; x++) {
                    size_t s = img.offset ((x - pad).clamp (0, img.width - 1), (y - pad).clamp (0, img.height - 1));
                    size_t d = big.offset (x, y);
                    for (int c = 0; c < 4; c++) big.data[d + c] = img.data[s + c];
                }
            Blur.gaussian (big, sx, sy);
            for (int y = 0; y < img.height; y++)
                Memory.copy (&img.data[img.offset (0, y)], &big.data[big.offset (pad, y + pad)], (size_t) img.width * 4 * sizeof (float));
        }
    }
}
