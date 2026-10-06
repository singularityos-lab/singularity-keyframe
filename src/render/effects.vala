using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public delegate void EffectBuild (PropGroup params);
    public delegate void EffectApply (EffectContext ctx, PropGroup fx, double t);
    public delegate double EffectMargin (PropGroup fx, double t);

    public class EffectDef {
        public string id;
        public string label;
        public string category;
        public EffectBuild build;
        public EffectApply? apply;
        public EffectMargin? margin;
        public bool control = false;
        public bool temporal = false;
        public bool from_plugin = false;

        public EffectDef (string id, string label, string category, owned EffectBuild build, owned EffectApply? apply, owned EffectMargin? margin = null) {
            this.id = id;
            this.label = label;
            this.category = category;
            this.build = (owned) build;
            this.apply = (owned) apply;
            this.margin = (owned) margin;
        }
    }

    public class EffectContext {
        public Renderer renderer;
        public Composition comp;
        public Layer layer;
        public double comp_time;
        public LayerBuffer buf;
        public RenderSettings settings;
        public int depth;
        public int effect_index;
        public bool adjustment = false;

        public double layer_time () {
            return layer.layer_time (comp_time);
        }

        public double px (double units) {
            return units * buf.scale;
        }

        public void to_pixel (double[] p, out double x, out double y) {
            buf.to_pixel (p[0], p[1], out x, out y);
        }

        public LayerBuffer upstream_at (double comp_t) {
            return renderer.layer_buffer_until (layer, comp_t, settings, depth, effect_index, buf.scale);
        }

        public FloatImage? other_layer_in_buffer (Layer? other, bool effects_and_masks = true) {
            if (other == null) return null;
            var comp_img = renderer.layer_comp_image (other, comp_time, settings, depth + 1, !effects_and_masks);
            if (comp_img == null) return new FloatImage (buf.img.width, buf.img.height);
            var out_img = new FloatImage (buf.img.width, buf.img.height);
            var world = layer.world_matrix (comp_time);
            var canvas = renderer.canvas_matrix (settings);
            var m = canvas.multiply (world).multiply (buf.pixel_to_layer ());
            Parallel.range (out_img.height, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < out_img.width; x++) {
                        var c = m.transform_point (Vec3 (x + 0.5, y + 0.5, 0));
                        float r, g, b, a;
                        Pixels.sample_premul (comp_img.img, c.x - comp_img.x, c.y - comp_img.y, out r, out g, out b, out a);
                        size_t o = out_img.offset (x, y);
                        out_img.data[o] = r;
                        out_img.data[o + 1] = g;
                        out_img.data[o + 2] = b;
                        out_img.data[o + 3] = a;
                    }
            });
            return out_img;
        }

        public Layer? layer_param (PropGroup fx, string key) {
            var p = fx.prop (key);
            if (p == null) return null;
            int idx = (int) Math.round (p.scalar_at (layer_time ()));
            if (idx < 0 || idx >= comp.layers.size) return null;
            var l = comp.layers[idx];
            return l == layer ? null : l;
        }
    }

    public class EffectRegistry {
        private static Gee.ArrayList<EffectDef>? defs = null;
        private static Gee.HashMap<string, EffectDef>? by_id = null;

        public static void ensure () {
            if (defs != null) return;
            defs = new Gee.ArrayList<EffectDef> ();
            by_id = new Gee.HashMap<string, EffectDef> ();
            EffectsBasic.register ();
            EffectsColor.register ();
            EffectsDistort.register ();
            EffectsGenerate.register ();
            EffectsKeying.register ();
            EffectsTime.register ();
            EffectsControls.register ();
            EffectsAdvanced.register ();
            Stabilizer.register ();
        }

        public static void add (EffectDef def) {
            if (defs == null) {
                defs = new Gee.ArrayList<EffectDef> ();
                by_id = new Gee.HashMap<string, EffectDef> ();
            }
            if (by_id.has_key (def.id)) defs.remove (by_id[def.id]);
            defs.add (def);
            by_id[def.id] = def;
        }

        public static EffectDef? get (string id) {
            ensure ();
            return by_id.has_key (id) ? by_id[id] : null;
        }

        public static Gee.List<EffectDef> all () {
            ensure ();
            return defs;
        }

        public static Gee.ArrayList<string> categories () {
            ensure ();
            var r = new Gee.ArrayList<string> ();
            foreach (var d in defs) if (!r.contains (d.category)) r.add (d.category);
            return r;
        }

        public static PropGroup? create (string id) {
            var d = get (id);
            if (d == null) return null;
            var g = new PropGroup ("effect." + id, id, d.label);
            d.build (g);
            return g;
        }

        public static PropGroup? add_to_layer (Layer l, string id) {
            var g = create (id);
            if (g == null) return null;
            var fx = l.effects;
            if (fx == null) {
                fx = new PropGroup ("effects", "effects", _("Effects"));
                l.root.add<PropGroup> (fx);
            }
            g.key = fx.unique_key (id);
            int n = 1;
            foreach (var c in fx.children) if (((PropGroup) c).type == g.type) n++;
            if (n > 1) g.name = "%s %d".printf (g.name, n);
            fx.add<PropGroup> (g);
            l.mark_changed ();
            return g;
        }

        public static string id_of (PropGroup fx) {
            return fx.type.has_prefix ("effect.") ? fx.type.substring (7) : fx.type;
        }
    }

    namespace FxUtil {
        public delegate void PixelFunc (ref float r, ref float g, ref float b, ref float a);

        public void per_pixel (FloatImage img, PixelFunc f) {
            Parallel.range (img.height, (s, e) => {
                for (size_t i = (size_t) s * img.width; i < (size_t) e * img.width; i++) {
                    float a = img.data[i * 4 + 3];
                    if (a <= 0) continue;
                    float r = img.data[i * 4] / a, g = img.data[i * 4 + 1] / a, b = img.data[i * 4 + 2] / a;
                    f (ref r, ref g, ref b, ref a);
                    img.data[i * 4] = r * a;
                    img.data[i * 4 + 1] = g * a;
                    img.data[i * 4 + 2] = b * a;
                    img.data[i * 4 + 3] = a;
                }
            });
        }

        public void mix_original (FloatImage img, FloatImage orig, double amount) {
            if (amount >= 0.9999) return;
            float k = (float) amount.clamp (0, 1);
            size_t n = img.pixel_count () * 4;
            for (size_t i = 0; i < n; i++) img.data[i] = orig.data[i] + (img.data[i] - orig.data[i]) * k;
        }

        public void rgb_to_hsl (float r, float g, float b, out float h, out float s, out float l) {
            float mx = float.max (r, float.max (g, b)), mn = float.min (r, float.min (g, b));
            l = (mx + mn) / 2;
            if (mx - mn < 1e-6f) {
                h = s = 0;
                return;
            }
            float d = mx - mn;
            s = l > 0.5f ? d / (2 - mx - mn) : d / (mx + mn);
            if (mx == r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (mx == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }

        private float hue2rgb (float p, float q, float t) {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0f / 6) return p + (q - p) * 6 * t;
            if (t < 0.5f) return q;
            if (t < 2.0f / 3) return p + (q - p) * (2.0f / 3 - t) * 6;
            return p;
        }

        public void hsl_to_rgb (float h, float s, float l, out float r, out float g, out float b) {
            if (s <= 0) {
                r = g = b = l;
                return;
            }
            float q = l < 0.5f ? l * (1 + s) : l + s - l * s;
            float p = 2 * l - q;
            r = hue2rgb (p, q, h + 1.0f / 3);
            g = hue2rgb (p, q, h);
            b = hue2rgb (p, q, h - 1.0f / 3);
        }

        public double[] point_in_pixels (EffectContext ctx, PropGroup fx, string key) {
            var v = fx.vec (key, ctx.layer_time ());
            double x, y;
            ctx.buf.to_pixel (v[0], v[1], out x, out y);
            return { x, y };
        }
    }
}
