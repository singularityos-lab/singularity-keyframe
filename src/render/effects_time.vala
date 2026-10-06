using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace EffectsTime {
        public FloatImage align (LayerBuffer? src, LayerBuffer target) {
            if (src == null) return new FloatImage (target.img.width, target.img.height);
            if (src.img.width == target.img.width && src.img.height == target.img.height
                && (src.x0 - target.x0).abs () < 1e-9 && (src.y0 - target.y0).abs () < 1e-9 && (src.scale - target.scale).abs () < 1e-12) return src.img;
            var out_img = new FloatImage (target.img.width, target.img.height);
            Parallel.range (out_img.height, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < out_img.width; x++) {
                        double lx, ly, px, py;
                        target.to_layer (x + 0.5, y + 0.5, out lx, out ly);
                        src.to_pixel (lx, ly, out px, out py);
                        float r, g, b, a;
                        Pixels.sample_premul (src.img, px, py, out r, out g, out b, out a);
                        size_t o = out_img.offset (x, y);
                        out_img.data[o] = r;
                        out_img.data[o + 1] = g;
                        out_img.data[o + 2] = b;
                        out_img.data[o + 3] = a;
                    }
            });
            return out_img;
        }

        public void register () {
            EffectRegistry.add (echo_def ());

            var posterize = new EffectDef ("posterize-time", _("Posterize Time"), _("Time"), (g) => {
                g.add<Property> (Factory.scalar ("fps", _("Frame Rate"), 12).range (0.1, 999).ui_range (1, 60));
            }, (ctx, fx, t) => {
                double fps = double.max (0.1, fx.num ("fps", t));
                double qt = Math.floor (t * fps + 1e-6) / fps;
                if ((qt - t).abs () < 1e-9) return;
                var up = ctx.upstream_at (ctx.layer.comp_time (qt));
                ctx.buf.img = align (up, ctx.buf);
            });
            posterize.temporal = true;
            EffectRegistry.add (posterize);

            var displace = new EffectDef ("time-displacement", _("Time Displacement"), _("Time"), (g) => {
                g.add<Property> (Factory.layer_ref ("map", _("Time Displacement Layer")));
                g.add<Property> (Factory.scalar ("max-time", _("Max Displacement Time [sec]"), 1).range (-100, 100).ui_range (-5, 5));
                g.add<Property> (Factory.scalar ("resolution", _("Time Resolution [fps]"), 30).range (1, 120));
                g.add<Property> (Factory.toggle ("stretch", _("Stretch Map to Fit"), true));
            }, (ctx, fx, t) => {
                var map_layer = ctx.layer_param (fx, "map");
                if (map_layer == null) return;
                var map = ctx.other_layer_in_buffer (map_layer);
                double maxt = fx.num ("max-time", t);
                double res = double.max (1, fx.num ("resolution", t));
                int levels = ((int) Math.ceil (maxt.abs () * 2 * res) + 1).clamp (2, 48);
                var slices = new FloatImage[levels];
                var cur = ctx.buf;
                for (int i = 0; i < levels; i++) {
                    double off = (i / (double) (levels - 1) - 0.5) * 2 * maxt;
                    var up = ctx.upstream_at (ctx.comp_time + off);
                    slices[i] = align (up, cur);
                }
                var out_img = new FloatImage (cur.img.width, cur.img.height);
                for (int y = 0; y < out_img.height; y++)
                    for (int x = 0; x < out_img.width; x++) {
                        float v = EffectsDistort.channel_value (map, x, y, 3);
                        int idx = ((int) Math.round (v * (levels - 1))).clamp (0, levels - 1);
                        size_t o = out_img.offset (x, y);
                        for (int c = 0; c < 4; c++) out_img.data[o + c] = slices[idx].data[o + c];
                    }
                ctx.buf.img = out_img;
            });
            displace.temporal = true;
            EffectRegistry.add (displace);
        }

        private EffectDef echo_def () {
            var d = new EffectDef ("echo", _("Echo"), _("Time"), (g) => {
                g.add<Property> (Factory.scalar ("time", _("Echo Time (seconds)"), -0.033).range (-60, 60).ui_range (-1, 1));
                g.add<Property> (Factory.scalar ("count", _("Number Of Echoes"), 1).range (0, 100).ui_range (0, 20));
                g.add<Property> (Factory.scalar ("start", _("Starting Intensity"), 1).range (0, 1));
                g.add<Property> (Factory.scalar ("decay", _("Decay"), 1).range (0, 1));
                g.add<Property> (Factory.choice ("operator", _("Echo Operator"), { _("Add"), _("Maximum"), _("Minimum"), _("Screen"), _("Composite In Back"), _("Composite In Front"), _("Blend") }));
            }, (ctx, fx, t) => {
                double et = fx.num ("time", t);
                int n = (int) Math.round (fx.num ("count", t));
                float start = (float) fx.num ("start", t);
                float decay = (float) fx.num ("decay", t);
                int op = fx.choice ("operator", t);
                var cur = ctx.buf;
                var frames = new Gee.ArrayList<FloatImage> ();
                frames.add (cur.img);
                for (int k = 1; k <= n; k++) {
                    var up = ctx.upstream_at (ctx.comp_time + et * k);
                    frames.add (align (up, cur));
                }
                var out_img = new FloatImage (cur.img.width, cur.img.height);
                size_t count = out_img.pixel_count ();
                if (op == 0 || op == 1 || op == 2 || op == 3 || op == 6) {
                    for (size_t i = 0; i < count; i++) {
                        float[] acc = { 0, 0, 0, 0 };
                        if (op == 2) acc = { float.MAX, float.MAX, float.MAX, float.MAX };
                        float wsum = 0;
                        for (int k = 0; k < frames.size; k++) {
                            float w = start * Math.powf (decay, k);
                            for (int c = 0; c < 4; c++) {
                                float v = frames[k].data[i * 4 + c] * w;
                                switch (op) {
                                    case 1: acc[c] = float.max (acc[c], v); break;
                                    case 2: acc[c] = float.min (acc[c], v); break;
                                    case 3: acc[c] = acc[c] + v - acc[c] * v.clamp (0, 1); break;
                                    default: acc[c] += v; break;
                                }
                            }
                            wsum += w;
                        }
                        for (int c = 0; c < 4; c++) {
                            float v = acc[c];
                            if (op == 6 && wsum > 0) v /= wsum;
                            if (c == 3) v = v.clamp (0, 1);
                            out_img.data[i * 4 + c] = v;
                        }
                    }
                } else {
                    bool front = op == 5;
                    for (int step = 0; step < frames.size; step++) {
                        int k = front ? step : frames.size - 1 - step;
                        float w = start * Math.powf (decay, k);
                        var src = frames[k];
                        for (size_t i = 0; i < count; i++) {
                            float sa = src.data[i * 4 + 3] * w;
                            if (sa <= 0) continue;
                            float inv = 1 - sa;
                            for (int c = 0; c < 3; c++) out_img.data[i * 4 + c] = src.data[i * 4 + c] * w + out_img.data[i * 4 + c] * inv;
                            out_img.data[i * 4 + 3] = sa + out_img.data[i * 4 + 3] * inv;
                        }
                    }
                }
                ctx.buf.img = out_img;
            });
            d.temporal = true;
            return d;
        }
    }
}
