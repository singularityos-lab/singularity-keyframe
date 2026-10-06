using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace EffectsDistort {
        public delegate bool WarpFunc (double x, double y, out double sx, out double sy);

        public FloatImage warp (FloatImage src, WarpFunc f) {
            var dst = new FloatImage (src.width, src.height);
            Parallel.range (dst.height, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < dst.width; x++) {
                        double sx, sy;
                        if (!f (x + 0.5, y + 0.5, out sx, out sy)) continue;
                        float r, g, b, a;
                        Pixels.sample_premul (src, sx, sy, out r, out g, out b, out a);
                        size_t o = dst.offset (x, y);
                        dst.data[o] = r;
                        dst.data[o + 1] = g;
                        dst.data[o + 2] = b;
                        dst.data[o + 3] = a;
                    }
            });
            return dst;
        }

        public float channel_value (FloatImage map, int x, int y, int channel) {
            size_t o = map.offset (x.clamp (0, map.width - 1), y.clamp (0, map.height - 1));
            float a = map.data[o + 3];
            if (channel == 4) return a;
            if (a <= 1e-6f) return 0.5f;
            float r = map.data[o] / a, g = map.data[o + 1] / a, b = map.data[o + 2] / a;
            switch (channel) {
                case 0: return Transfer.linear_to_srgb (r.clamp (0, 1));
                case 1: return Transfer.linear_to_srgb (g.clamp (0, 1));
                case 2: return Transfer.linear_to_srgb (b.clamp (0, 1));
                case 5: return 0.5f;
                default: return Transfer.linear_to_srgb (Pixels.luma (r, g, b).clamp (0, 1));
            }
        }

        public double wave_shape (int type, double phase, int seed) {
            double p = phase - Math.floor (phase);
            switch (type) {
                case 1: return p < 0.5 ? 1 : -1;
                case 2: return 1 - 4 * (p - 0.5).abs ();
                case 3: return 2 * p - 1;
                case 4: return Math.sqrt (double.max (0, 1 - Math.pow (2 * p - 1, 2))) * (p < 0.5 ? 1 : -1);
                case 5: return Math.sqrt (double.max (0, 1 - Math.pow (4 * (p < 0.5 ? p : p - 0.5) - 1, 2)));
                case 6: return -Math.sqrt (double.max (0, 1 - Math.pow (4 * (p < 0.5 ? p : p - 0.5) - 1, 2)));
                case 7: return Noise.hash01 ((int) Math.floor (phase * 8), seed, 41) * 2 - 1;
                case 8: return Noise.perlin1 (phase * 4, seed).clamp (-1, 1);
                default: return Math.sin (phase * 2 * Math.PI);
            }
        }

        public void register () {
            EffectRegistry.add (new EffectDef ("displacement-map", _("Displacement Map"), _("Distort"), (g) => {
                g.add<Property> (Factory.layer_ref ("map", _("Displacement Map Layer")));
                string[] chans = { _("Red"), _("Green"), _("Blue"), _("Luminance"), _("Alpha"), _("Off") };
                g.add<Property> (Factory.choice ("horizontal-channel", _("Use For Horizontal Displacement"), chans, 0));
                g.add<Property> (Factory.scalar ("max-horizontal", _("Max Horizontal Displacement"), 5).range (-32000, 32000).ui_range (-100, 100));
                g.add<Property> (Factory.choice ("vertical-channel", _("Use For Vertical Displacement"), chans, 1));
                g.add<Property> (Factory.scalar ("max-vertical", _("Max Vertical Displacement"), 5).range (-32000, 32000).ui_range (-100, 100));
                g.add<Property> (Factory.toggle ("wrap", _("Wrap Pixels Around"), false));
            }, (ctx, fx, t) => {
                var map_layer = ctx.layer_param (fx, "map");
                FloatImage map = map_layer != null ? ctx.other_layer_in_buffer (map_layer) : ctx.buf.img.copy ();
                int hc = fx.choice ("horizontal-channel", t), vc = fx.choice ("vertical-channel", t);
                double mh = ctx.px (fx.num ("max-horizontal", t)), mv = ctx.px (fx.num ("max-vertical", t));
                bool wrap = fx.toggle ("wrap", t);
                var src = ctx.buf.img;
                int w = src.width, h = src.height;
                ctx.buf.img = warp (src, (x, y, out sx, out sy) => {
                    int ix = (int) x, iy = (int) y;
                    double dx = (channel_value (map, ix, iy, hc) - 0.5) * 2 * mh;
                    double dy = (channel_value (map, ix, iy, vc) - 0.5) * 2 * mv;
                    sx = x + dx;
                    sy = y + dy;
                    if (wrap) {
                        sx = sx - Math.floor (sx / w) * w;
                        sy = sy - Math.floor (sy / h) * h;
                    }
                    return true;
                });
            }, (fx, t) => double.max (fx.num ("max-horizontal", t).abs (), fx.num ("max-vertical", t).abs ())));

            EffectRegistry.add (new EffectDef ("wave-warp", _("Wave Warp"), _("Distort"), (g) => {
                g.add<Property> (Factory.choice ("type", _("Wave Type"), { _("Sine"), _("Square"), _("Triangle"), _("Sawtooth"), _("Circle"), _("Semicircle"), _("Uncircle"), _("Noise"), _("Smooth Noise") }));
                g.add<Property> (Factory.scalar ("height", _("Wave Height"), 10).range (-10000, 10000).ui_range (-100, 100));
                g.add<Property> (Factory.scalar ("width", _("Wave Width"), 40).range (1, 10000).ui_range (1, 500));
                g.add<Property> (Factory.angle ("direction", _("Direction"), 90));
                g.add<Property> (Factory.scalar ("speed", _("Wave Speed"), 1).range (-100, 100).ui_range (-10, 10));
                g.add<Property> (Factory.choice ("pinning", _("Pinning"), { _("None"), _("All Edges"), _("Left Edge"), _("Top Edge"), _("Right Edge"), _("Bottom Edge") }));
                g.add<Property> (Factory.angle ("phase", _("Phase"), 0));
            }, (ctx, fx, t) => {
                int type = fx.choice ("type", t);
                double amp = ctx.px (fx.num ("height", t));
                double wl = ctx.px (double.max (1, fx.num ("width", t)));
                double dir = (fx.num ("direction", t) - 90) * Math.PI / 180.0;
                double phase = fx.num ("phase", t) / 360.0 + fx.num ("speed", t) * t;
                int pin = fx.choice ("pinning", t);
                var src = ctx.buf.img;
                double w = src.width, h = src.height;
                double ux = Math.cos (dir), uy = Math.sin (dir);
                ctx.buf.img = warp (src, (x, y, out sx, out sy) => {
                    double along = x * ux + y * uy;
                    double d = wave_shape (type, along / wl - phase, 7) * amp;
                    double k = 1;
                    switch (pin) {
                        case 1: k = double.min (double.min (x, w - x), double.min (y, h - y)) / double.max (1, double.min (w, h) / 2); break;
                        case 2: k = x / w; break;
                        case 3: k = y / h; break;
                        case 4: k = (w - x) / w; break;
                        case 5: k = (h - y) / h; break;
                    }
                    d *= k.clamp (0, 1);
                    sx = x + -uy * d;
                    sy = y + ux * d;
                    return true;
                });
            }, (fx, t) => fx.num ("height", t).abs ()));

            EffectRegistry.add (new EffectDef ("mirror", _("Mirror"), _("Distort"), (g) => {
                g.add<Property> (Factory.point ("center", _("Reflection Center"), { 0, 0 }));
                g.add<Property> (Factory.angle ("angle", _("Reflection Angle"), 0));
            }, (ctx, fx, t) => {
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double a = fx.num ("angle", t) * Math.PI / 180.0;
                double nx = Math.cos (a), ny = Math.sin (a);
                ctx.buf.img = warp (ctx.buf.img, (x, y, out sx, out sy) => {
                    double d = (x - c[0]) * nx + (y - c[1]) * ny;
                    if (d > 0) {
                        sx = x - 2 * d * nx;
                        sy = y - 2 * d * ny;
                    } else {
                        sx = x;
                        sy = y;
                    }
                    return true;
                });
            }));

            EffectRegistry.add (new EffectDef ("turbulent-displace", _("Turbulent Displace"), _("Distort"), (g) => {
                g.add<Property> (Factory.scalar ("amount", _("Amount"), 50).range (-1000, 1000).ui_range (-200, 200));
                g.add<Property> (Factory.scalar ("size", _("Size"), 100).range (2, 1000).ui_range (2, 500));
                g.add<Property> (Factory.point ("offset", _("Offset (Turbulence)"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("complexity", _("Complexity"), 1).range (1, 10));
                g.add<Property> (Factory.angle ("evolution", _("Evolution"), 0));
                g.add<Property> (Factory.scalar ("seed", _("Random Seed"), 0).range (0, 100000));
            }, (ctx, fx, t) => {
                double amt = ctx.px (fx.num ("amount", t)) / 10.0;
                double size = ctx.px (double.max (2, fx.num ("size", t)));
                var off = fx.vec ("offset", t);
                int octaves = (int) fx.num ("complexity", t);
                double evo = fx.num ("evolution", t) / 360.0;
                int seed = (int) fx.num ("seed", t);
                double ox = ctx.px (off[0]), oy = ctx.px (off[1]);
                ctx.buf.img = warp (ctx.buf.img, (x, y, out sx, out sy) => {
                    double fx1 = 0, fy1 = 0, amp = 1, freq = 1, norm = 0;
                    for (int o = 0; o < int.max (1, octaves); o++) {
                        double u = (x + ox) / size * freq, v = (y + oy) / size * freq;
                        fx1 += Noise.perlin3 (u, v, evo, seed + o) * amp;
                        fy1 += Noise.perlin3 (u + 31.4, v - 17.7, evo, seed + o + 99) * amp;
                        norm += amp;
                        amp *= 0.5;
                        freq *= 2;
                    }
                    sx = x + fx1 / norm * amt * 4;
                    sy = y + fy1 / norm * amt * 4;
                    return true;
                });
            }, (fx, t) => fx.num ("amount", t).abs () * 0.4));

            EffectRegistry.add (new EffectDef ("twirl", _("Twirl"), _("Distort"), (g) => {
                g.add<Property> (Factory.angle ("angle", _("Angle"), 90));
                g.add<Property> (Factory.scalar ("radius", _("Twirl Radius"), 30).range (0, 100));
                g.add<Property> (Factory.point ("center", _("Twirl Center"), { 0, 0 }));
            }, (ctx, fx, t) => {
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double ang = fx.num ("angle", t) * Math.PI / 180.0;
                double rad = double.max (1, fx.num ("radius", t) / 100.0 * double.min (ctx.buf.img.width, ctx.buf.img.height));
                ctx.buf.img = warp (ctx.buf.img, (x, y, out sx, out sy) => {
                    double dx = x - c[0], dy = y - c[1];
                    double d = Math.hypot (dx, dy);
                    if (d >= rad) {
                        sx = x;
                        sy = y;
                        return true;
                    }
                    double k = 1 - d / rad;
                    double a = -ang * k * k;
                    sx = c[0] + dx * Math.cos (a) - dy * Math.sin (a);
                    sy = c[1] + dx * Math.sin (a) + dy * Math.cos (a);
                    return true;
                });
            }));

            EffectRegistry.add (new EffectDef ("bulge", _("Bulge"), _("Distort"), (g) => {
                g.add<Property> (Factory.scalar ("horizontal-radius", _("Horizontal Radius"), 50).range (0, 10000).ui_range (0, 500));
                g.add<Property> (Factory.scalar ("vertical-radius", _("Vertical Radius"), 50).range (0, 10000).ui_range (0, 500));
                g.add<Property> (Factory.point ("center", _("Bulge Center"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("height", _("Bulge Height"), 1).range (-4, 4));
                g.add<Property> (Factory.toggle ("pin-edges", _("Pin All Edges"), false));
            }, (ctx, fx, t) => {
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double rx = double.max (1, ctx.px (fx.num ("horizontal-radius", t))), ry = double.max (1, ctx.px (fx.num ("vertical-radius", t)));
                double hgt = fx.num ("height", t);
                ctx.buf.img = warp (ctx.buf.img, (x, y, out sx, out sy) => {
                    double u = (x - c[0]) / rx, v = (y - c[1]) / ry;
                    double d = Math.sqrt (u * u + v * v);
                    if (d >= 1 || d < 1e-9) {
                        sx = x;
                        sy = y;
                        return true;
                    }
                    double k = Math.pow (d, hgt >= 0 ? 1 + hgt * (1 - d) : 1.0 / (1 - hgt * (1 - d))) / d;
                    sx = c[0] + u * k * rx;
                    sy = c[1] + v * k * ry;
                    return true;
                });
            }));

            EffectRegistry.add (new EffectDef ("offset", _("Offset"), _("Distort"), (g) => {
                g.add<Property> (Factory.point ("shift", _("Shift Center To"), { 0, 0 }));
                g.add<Property> (Factory.percent ("blend", _("Blend With Original"), 0).range (0, 100));
            }, (ctx, fx, t) => {
                var src = ctx.buf.img;
                var orig = src.copy ();
                var sh = FxUtil.point_in_pixels (ctx, fx, "shift");
                double dx = sh[0] - src.width / 2.0, dy = sh[1] - src.height / 2.0;
                int w = src.width, h = src.height;
                ctx.buf.img = warp (src, (x, y, out sx, out sy) => {
                    sx = x - dx;
                    sy = y - dy;
                    sx = sx - Math.floor (sx / w) * w;
                    sy = sy - Math.floor (sy / h) * h;
                    return true;
                });
                FxUtil.mix_original (ctx.buf.img, orig, 1 - fx.num ("blend", t) / 100.0);
            }));

            EffectRegistry.add (new EffectDef ("polar-coordinates", _("Polar Coordinates"), _("Distort"), (g) => {
                g.add<Property> (Factory.percent ("interpolation", _("Interpolation"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("type", _("Type of Conversion"), { _("Rect to Polar"), _("Polar to Rect") }));
            }, (ctx, fx, t) => {
                double k = fx.num ("interpolation", t) / 100.0;
                bool to_polar = fx.choice ("type", t) == 0;
                var src = ctx.buf.img;
                double w = src.width, h = src.height, cx = w / 2, cy = h / 2;
                double maxr = Math.hypot (cx, cy);
                ctx.buf.img = warp (src, (x, y, out sx, out sy) => {
                    double px, py;
                    if (to_polar) {
                        double ang = Math.atan2 (x - cx, -(y - cy));
                        if (ang < 0) ang += 2 * Math.PI;
                        double r = Math.hypot (x - cx, y - cy);
                        px = ang / (2 * Math.PI) * w;
                        py = r / maxr * h;
                    } else {
                        double ang = x / w * 2 * Math.PI;
                        double r = y / h * maxr;
                        px = cx + Math.sin (ang) * r;
                        py = cy - Math.cos (ang) * r;
                    }
                    sx = x + (px - x) * k;
                    sy = y + (py - y) * k;
                    return true;
                });
            }));

            EffectRegistry.add (new EffectDef ("spherize", _("Spherize"), _("Distort"), (g) => {
                g.add<Property> (Factory.scalar ("radius", _("Radius"), 100).range (0, 10000).ui_range (0, 1000));
                g.add<Property> (Factory.point ("center", _("Center of Sphere"), { 0, 0 }));
            }, (ctx, fx, t) => {
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double rad = double.max (1, ctx.px (fx.num ("radius", t)));
                ctx.buf.img = warp (ctx.buf.img, (x, y, out sx, out sy) => {
                    double dx = (x - c[0]) / rad, dy = (y - c[1]) / rad;
                    double d = Math.hypot (dx, dy);
                    if (d >= 1 || d < 1e-9) {
                        sx = x;
                        sy = y;
                        return true;
                    }
                    double k = Math.asin (d) / (Math.PI / 2) / d;
                    sx = c[0] + dx * k * rad;
                    sy = c[1] + dy * k * rad;
                    return true;
                });
            }));

            EffectRegistry.add (new EffectDef ("mesh-warp", _("Mesh Warp"), _("Distort"), (g) => {
                g.attrs["rows"] = "3";
                g.attrs["columns"] = "3";
                var pts = new PropGroup ("mesh-warp.points", "points", _("Distortion Mesh"));
                for (int r = 0; r <= 3; r++)
                    for (int c = 0; c <= 3; c++)
                        pts.add<Property> (Factory.vec ("p%d-%d".printf (r, c), _("Vertex %d, %d").printf (r + 1, c + 1), { 0, 0 }));
                g.add<PropGroup> (pts);
            }, (ctx, fx, t) => {
                int rows = int.parse (fx.attr ("rows", "3")).clamp (1, 31), cols = int.parse (fx.attr ("columns", "3")).clamp (1, 31);
                var pts = fx.group ("points");
                if (pts == null) return;
                var src = ctx.buf.img;
                double w = src.width, h = src.height;
                var ox = new double[(rows + 1) * (cols + 1)];
                var oy = new double[(rows + 1) * (cols + 1)];
                for (int r = 0; r <= rows; r++)
                    for (int c = 0; c <= cols; c++) {
                        var p = pts.prop ("p%d-%d".printf (r, c));
                        var v = p != null ? p.value_at (t) : new double[] { 0, 0 };
                        ox[r * (cols + 1) + c] = ctx.px (v[0]);
                        oy[r * (cols + 1) + c] = ctx.px (v[1]);
                    }
                var dst = new FloatImage (src.width, src.height);
                for (int r = 0; r < rows; r++)
                    for (int c = 0; c < cols; c++) {
                        int[] ids = { r * (cols + 1) + c, r * (cols + 1) + c + 1, (r + 1) * (cols + 1) + c + 1, (r + 1) * (cols + 1) + c };
                        int[] rr = { r, r, r + 1, r + 1 };
                        int[] cc = { c, c + 1, c + 1, c };
                        var sp = new double[8];
                        var dp = new double[8];
                        for (int k = 0; k < 4; k++) {
                            sp[k * 2] = cc[k] * w / cols;
                            sp[k * 2 + 1] = rr[k] * h / rows;
                            dp[k * 2] = sp[k * 2] + ox[ids[k]];
                            dp[k * 2 + 1] = sp[k * 2 + 1] + oy[ids[k]];
                        }
                        Puppet.raster_triangle (src, dst, { dp[0], dp[1], dp[2], dp[3], dp[4], dp[5] }, { sp[0], sp[1], sp[2], sp[3], sp[4], sp[5] });
                        Puppet.raster_triangle (src, dst, { dp[0], dp[1], dp[4], dp[5], dp[6], dp[7] }, { sp[0], sp[1], sp[4], sp[5], sp[6], sp[7] });
                    }
                ctx.buf.img = dst;
            }));

            EffectRegistry.add (new EffectDef ("optics-compensation", _("Optics Compensation"), _("Distort"), (g) => {
                g.add<Property> (Factory.scalar ("fov", _("Field Of View (FOV)"), 0).range (0, 180));
                g.add<Property> (Factory.toggle ("reverse", _("Reverse Lens Distortion"), false));
                g.add<Property> (Factory.point ("center", _("View Center"), { 0, 0 }));
            }, (ctx, fx, t) => {
                double fov = fx.num ("fov", t) * Math.PI / 180.0;
                if (fov < 1e-4) return;
                bool rev = fx.toggle ("reverse", t);
                var c = FxUtil.point_in_pixels (ctx, fx, "center");
                double half = Math.hypot (ctx.buf.img.width, ctx.buf.img.height) / 2;
                double f = half / Math.tan (fov / 2);
                ctx.buf.img = warp (ctx.buf.img, (x, y, out sx, out sy) => {
                    double dx = x - c[0], dy = y - c[1];
                    double r = Math.hypot (dx, dy);
                    if (r < 1e-9) {
                        sx = x;
                        sy = y;
                        return true;
                    }
                    double nr = rev ? f * Math.atan (r / f) : f * Math.tan (double.min (r / f, 1.5));
                    sx = c[0] + dx / r * nr;
                    sy = c[1] + dy / r * nr;
                    return true;
                });
            }));
        }
    }
}
