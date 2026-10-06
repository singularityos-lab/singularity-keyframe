using Singularity.Vector;
using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class TextGlyph {
        public int char_index;
        public int word_index;
        public int line_index;
        public bool is_space;
        public double x;
        public double y;
        public double advance;
        public Gee.ArrayList<BezPath> paths = new Gee.ArrayList<BezPath> ();
        public double[] offset = { 0, 0 };
        public double[] scale = { 100, 100 };
        public double rotation = 0;
        public double skew = 0;
        public double[] anchor = { 0, 0 };
        public double opacity = 100;
        public double[] fill;
        public double[] stroke;
        public double stroke_width;
        public double tracking = 0;
        public double blur = 0;
        public double[] line_shift = { 0, 0 };
    }

    public class TextLayout {
        public Gee.ArrayList<TextGlyph> glyphs = new Gee.ArrayList<TextGlyph> ();
        public int char_count = 0;
        public int word_count = 0;
        public int line_count = 0;
        public int nonspace_count = 0;
    }

    public class TextRenderer {
        public static Pango.FontDescription font_description (TextDocument d) {
            var fd = Pango.FontDescription.from_string (d.font);
            fd.set_absolute_size (d.size * Pango.SCALE);
            fd.set_weight ((Pango.Weight) d.weight.clamp (100, 1000));
            fd.set_style (d.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            if (d.variations != "") fd.set_variations (d.variations);
            return fd;
        }

        public static Pango.Layout make_layout (TextDocument d, Cairo.Context cr) {
            var layout = Pango.cairo_create_layout (cr);
            var ctx = layout.get_context ();
            Pango.cairo_context_set_resolution (ctx, 72);
            var fo = new Cairo.FontOptions ();
            fo.set_hint_style (Cairo.HintStyle.NONE);
            fo.set_hint_metrics (Cairo.HintMetrics.OFF);
            Pango.cairo_context_set_font_options (ctx, fo);
            layout.context_changed ();
            layout.set_font_description (font_description (d));
            string text = d.all_caps ? d.text.up () : d.text;
            layout.set_text (text, -1);
            var attrs = new Pango.AttrList ();
            if (d.tracking != 0) attrs.insert (Pango.attr_letter_spacing_new ((int) (d.tracking / 1000.0 * d.size * Pango.SCALE)));
            if (d.leading > 0) attrs.insert (Pango.attr_line_height_new_absolute ((int) (d.leading * Pango.SCALE)));
            string features = d.features;
            if (d.small_caps) features = features == "" ? "smcp" : features + ",smcp";
            if (features != "") attrs.insert (new Pango.AttrFontFeatures (features));
            if (d.baseline_shift != 0) attrs.insert (Pango.attr_rise_new ((int) (-d.baseline_shift * Pango.SCALE)));
            layout.set_attributes (attrs);
            switch (d.justify) {
                case 1: layout.set_alignment (Pango.Alignment.CENTER); break;
                case 2: layout.set_alignment (Pango.Alignment.RIGHT); break;
                case 3:
                    layout.set_alignment (Pango.Alignment.LEFT);
                    layout.set_justify (true);
                    break;
                default: layout.set_alignment (Pango.Alignment.LEFT); break;
            }
            if (d.is_box ()) {
                layout.set_width ((int) (d.box_width * Pango.SCALE));
                layout.set_wrap (Pango.WrapMode.WORD_CHAR);
                if (d.box_height > 0) layout.set_height ((int) (d.box_height * Pango.SCALE));
            }
            if (d.first_indent != 0) layout.set_indent ((int) (d.first_indent * Pango.SCALE));
            return layout;
        }

        public static TextLayout layout_glyphs (TextDocument d) {
            var result = new TextLayout ();
            var surface = new Cairo.ImageSurface (Cairo.Format.A8, 1, 1);
            var cr = new Cairo.Context (surface);
            var layout = make_layout (d, cr);
            string text = layout.get_text ();
            int baseline0 = layout.get_baseline ();
            Pango.Rectangle ink, logical;
            layout.get_extents (out ink, out logical);
            double origin_x = 0, origin_y = 0;
            if (d.is_box ()) {
                origin_x = 0;
                origin_y = 0;
            } else {
                double lw = logical.width / (double) Pango.SCALE;
                origin_x = d.justify == 1 ? -lw / 2 : (d.justify == 2 ? -lw : 0);
                origin_y = -baseline0 / (double) Pango.SCALE;
                if (d.justify == 1 || d.justify == 2) origin_x = -logical.x / (double) Pango.SCALE + origin_x;
            }
            var iter = layout.get_iter ();
            int line_index = 0;
            unowned Pango.LayoutLine? prev_line = null;
            do {
                unowned Pango.LayoutLine line = iter.get_line_readonly ();
                if (prev_line != null && line != prev_line) line_index++;
                prev_line = line;
                unowned Pango.LayoutRun? run = iter.get_run_readonly ();
                if (run == null) continue;
                int baseline = iter.get_baseline ();
                Pango.Rectangle run_logical;
                iter.get_run_extents (null, out run_logical);
                double x = run_logical.x / (double) Pango.SCALE;
                unowned Pango.GlyphString gs = run.glyphs;
                var font = run.item.analysis.font;
                for (int i = 0; i < gs.num_glyphs; i++) {
                    var gi = gs.glyphs[i];
                    int cluster = gs.log_clusters[i];
                    int byte_index = run.item.offset + cluster;
                    var g = new TextGlyph ();
                    g.char_index = text.char_count (byte_index);
                    unichar ch = text.get_char (byte_index);
                    g.is_space = ch.isspace ();
                    g.line_index = line_index;
                    g.advance = gi.geometry.width / (double) Pango.SCALE;
                    g.x = origin_x + x + gi.geometry.x_offset / (double) Pango.SCALE;
                    g.y = origin_y + (baseline + gi.geometry.y_offset) / (double) Pango.SCALE;
                    var single = new Pango.GlyphString ();
                    single.set_size (1);
                    single.glyphs[0] = gi;
                    single.glyphs[0].geometry.x_offset = 0;
                    single.glyphs[0].geometry.y_offset = 0;
                    single.log_clusters[0] = 0;
                    cr.new_path ();
                    cr.move_to (0, 0);
                    Pango.cairo_glyph_string_path (cr, font, single);
                    foreach (var p in BezPath.from_cairo (cr)) g.paths.add (p);
                    x += gi.geometry.width / (double) Pango.SCALE;
                    result.glyphs.add (g);
                }
            } while (iter.next_run ());
            result.glyphs.sort ((a, b) => a.char_index - b.char_index);
            int word = 0;
            bool in_word = false;
            int nonspace = 0;
            foreach (var g in result.glyphs) {
                if (g.is_space) {
                    if (in_word) word++;
                    in_word = false;
                } else {
                    in_word = true;
                    nonspace++;
                }
                g.word_index = word;
            }
            result.char_count = text.char_count ();
            result.word_count = word + (in_word ? 1 : 0);
            result.line_count = line_index + 1;
            result.nonspace_count = nonspace;
            return result;
        }

        public static double shape_value (string shape, double pos, double start, double end, double smooth, double ease_high, double ease_low) {
            double lo = double.min (start, end), hi = double.max (start, end);
            double width = hi - lo;
            if (width <= 1e-9) return 0;
            double u = (pos - lo) / width;
            double v;
            switch (shape) {
                case "ramp-up":
                    v = u.clamp (0, 1);
                    if (pos > hi) v = 1;
                    break;
                case "ramp-down":
                    v = 1 - u.clamp (0, 1);
                    if (pos < lo) v = 1;
                    break;
                case "triangle":
                    v = u < 0 || u > 1 ? 0 : 1 - (2 * u - 1).abs ();
                    break;
                case "round":
                    v = u < 0 || u > 1 ? 0 : Math.sqrt (double.max (0, 1 - Math.pow (2 * u - 1, 2)));
                    break;
                case "smooth":
                    v = u < 0 || u > 1 ? 0 : 0.5 - 0.5 * Math.cos (u * 2 * Math.PI);
                    break;
                default:
                    v = u >= 0 && u < 1 ? 1 : 0;
                    break;
            }
            if (ease_high != 0 || ease_low != 0) {
                double eh = ease_high.clamp (-1, 1), el = ease_low.clamp (-1, 1);
                double k = v;
                double eased = k < 0.5 ? 0.5 * Math.pow (2 * k, 1 + el) : 1 - 0.5 * Math.pow (2 * (1 - k), 1 + eh);
                v = eased;
            }
            return v;
        }

        public static double selector_amount (PropGroup sel, TextGlyph g, TextLayout tl, double t, Layer? layer) {
            string based = sel.attr ("based-on", "characters");
            int index, total;
            switch (based) {
                case "words":
                    index = g.word_index;
                    total = int.max (1, tl.word_count);
                    break;
                case "lines":
                    index = g.line_index;
                    total = int.max (1, tl.line_count);
                    break;
                case "characters-excluding-spaces":
                    index = 0;
                    foreach (var o in tl.glyphs) if (o.char_index < g.char_index && !o.is_space) index++;
                    total = int.max (1, tl.nonspace_count);
                    if (g.is_space) return 0;
                    break;
                default:
                    index = g.char_index;
                    total = int.max (1, tl.char_count);
                    break;
            }
            if (sel.type == "text.selector.wiggly") {
                double wps = sel.num ("wiggles", t);
                double corr = sel.num ("correlation", t) / 100.0;
                double tp = sel.num ("temporal-phase", t) / 360.0, sp = sel.num ("spatial-phase", t) / 360.0;
                int seed = (int) sel.num ("seed", t);
                double n = Noise.perlin2 (t * wps + tp, index * (1 - corr.clamp (0, 0.99)) + sp, seed);
                double mx = sel.num ("max", t) / 100.0, mn = sel.num ("min", t) / 100.0;
                return mn + (mx - mn) * (n.clamp (-1, 1) * 0.5 + 0.5);
            }
            if (sel.type == "text.selector.expression") {
                var p = sel.prop ("amount");
                if (p == null) return 1;
                TextExpressionVars.index = index + 1;
                TextExpressionVars.total = total;
                TextExpressionVars.selector_value = 100;
                TextExpressionVars.active = true;
                double v = p.scalar_at (t) / 100.0;
                TextExpressionVars.active = false;
                return v;
            }
            int order = index;
            if (sel.attr ("randomize", "false") == "true") {
                int seed = (int) sel.num ("seed", t);
                var perm = new int[total];
                for (int i = 0; i < total; i++) perm[i] = i;
                for (int i = total - 1; i > 0; i--) {
                    int j = (int) (Noise.hash01 (i, seed, 991) * (i + 1)) % (i + 1);
                    int tmp = perm[i];
                    perm[i] = perm[j];
                    perm[j] = tmp;
                }
                order = perm[index.clamp (0, total - 1)];
            }
            double start = sel.num ("start", t), end = sel.num ("end", t), off = sel.num ("offset", t);
            double pos;
            if (sel.attr ("units", "percent") == "index") {
                pos = order + 0.5;
                start += off;
                end += off;
            } else {
                pos = (order + 0.5) / total * 100.0;
                start += off;
                end += off;
            }
            double v = shape_value (sel.attr ("shape", "square"), pos, start, end, sel.num ("smoothness", t) / 100.0, sel.num ("ease-high", t) / 100.0, sel.num ("ease-low", t) / 100.0);
            return v * sel.num ("amount", t) / 100.0;
        }

        public static double combine (double acc, double v, string mode, bool first) {
            if (first) {
                if (mode == "subtract") return 1 - v;
                return v;
            }
            switch (mode) {
                case "subtract": return acc * (1 - v);
                case "intersect": return acc * v;
                case "min": return double.min (acc, v);
                case "max": return double.max (acc, v);
                case "difference": return (acc - v).abs ();
                default: return double.min (1, acc + v);
            }
        }

        public static void apply_animators (PropGroup text, TextLayout tl, double t, Layer? layer, TextDocument d) {
            var animators = text.group ("animators");
            foreach (var g in tl.glyphs) {
                g.fill = d.fill;
                g.stroke = d.stroke;
                g.stroke_width = d.stroke_width;
            }
            if (animators == null) return;
            foreach (var an in animators.groups_of_type ("text.animator")) {
                if (!an.enabled) continue;
                var sels = an.group ("selectors");
                var props = an.group ("properties");
                if (props == null) continue;
                foreach (var g in tl.glyphs) {
                    double amt = 1;
                    bool first = true;
                    if (sels != null) {
                        foreach (var c in sels.children) {
                            var sel = c as PropGroup;
                            if (sel == null || !sel.enabled) continue;
                            double v = selector_amount (sel, g, tl, t, layer);
                            amt = combine (amt, v, sel.attr ("mode", "add"), first);
                            first = false;
                        }
                    }
                    if (amt == 0) continue;
                    foreach (var pc in props.children) {
                        var p = pc as Property;
                        if (p == null) continue;
                        var val = p.value_at (t);
                        switch (p.key) {
                            case "position":
                                g.offset[0] += val[0] * amt;
                                g.offset[1] += val[1] * amt;
                                break;
                            case "anchor":
                                g.anchor[0] += val[0] * amt;
                                g.anchor[1] += val[1] * amt;
                                break;
                            case "scale":
                                g.scale[0] += (val[0] - 100) * amt;
                                g.scale[1] += (val[1] - 100) * amt;
                                break;
                            case "rotation":
                                g.rotation += val[0] * amt;
                                break;
                            case "skew":
                                g.skew += val[0] * amt;
                                break;
                            case "opacity":
                                g.opacity += (val[0] - 100) * amt.abs ();
                                break;
                            case "fill-color":
                                g.fill = lerp4 (g.fill, val, amt.abs ());
                                break;
                            case "stroke-color":
                                g.stroke = lerp4 (g.stroke, val, amt.abs ());
                                break;
                            case "stroke-width":
                                g.stroke_width += (val[0] - g.stroke_width) * amt.abs ();
                                break;
                            case "tracking":
                                g.tracking += val[0] * amt;
                                break;
                            case "line-spacing":
                                g.line_shift[0] += val[0] * amt * g.line_index;
                                g.line_shift[1] += val[1] * amt * g.line_index;
                                break;
                            case "blur":
                                g.blur = double.max (g.blur, double.max (val[0], val.length > 1 ? val[1] : val[0]) * amt.abs ());
                                break;
                            case "character-offset":
                                break;
                        }
                    }
                }
            }
            double extra = 0;
            int line = -1;
            foreach (var g in tl.glyphs) {
                if (g.line_index != line) {
                    line = g.line_index;
                    extra = 0;
                }
                g.x += extra;
                extra += g.tracking / 1000.0 * d.size;
            }
        }

        private static double[] lerp4 (double[] a, double[] b, double t) {
            var r = new double[4];
            for (int i = 0; i < 4; i++) {
                double av = i < a.length ? a[i] : 1, bv = i < b.length ? b[i] : 1;
                r[i] = av + (bv - av) * t.clamp (0, 1);
            }
            return r;
        }

        public static Mat4 glyph_matrix (TextGlyph g, BezPath? path, PropGroup? po, double t, double total_width) {
            double cx = g.advance / 2;
            double gx = g.x + g.line_shift[0], gy = g.y + g.line_shift[1];
            var base_m = Mat4.translation (gx + cx, gy, 0);
            if (path != null && path.count > 1) {
                bool reverse = po != null && po.toggle ("reverse", t);
                var pth = reverse ? path.reversed () : path;
                double len = pth.length ();
                double first = po != null ? po.num ("first-margin", t) : 0;
                double last = po != null ? po.num ("last-margin", t) : 0;
                double along = first + g.x + cx;
                if (po != null && po.toggle ("force-alignment", t) && total_width > 0) {
                    along = first + (g.x + cx) / total_width * (len - first - last);
                }
                double angle;
                var pt = pth.point_at_length (along.clamp (0, len), out angle);
                bool perp = po == null || po.toggle ("perpendicular", t);
                base_m = Mat4.translation (pt.x, pt.y, 0);
                if (perp) base_m = base_m.multiply (Mat4.rotation_z (angle * 180.0 / Math.PI));
            }
            var m = base_m.multiply (Mat4.translation (g.offset[0], g.offset[1], 0));
            m = m.multiply (Mat4.rotation_z (g.rotation));
            m = m.multiply (Mat4.skew (g.skew, 0));
            m = m.multiply (Mat4.scaling (g.scale[0] / 100.0, g.scale[1] / 100.0, 1));
            m = m.multiply (Mat4.translation (-cx - g.anchor[0], -g.anchor[1], 0));
            return m;
        }

        public static Rect bounds (TextLayout tl, PropGroup text, BezPath? path, double t, TextDocument d) {
            var r = Rect.empty ();
            bool any = false;
            var po = text.group ("path-options");
            double tw = total_width (tl);
            foreach (var g in tl.glyphs) {
                var m = glyph_matrix (g, path, po, t, tw);
                foreach (var p in g.paths) {
                    var c = p.copy ();
                    c.transform (m);
                    var pr = Rect.empty ();
                    c.bounds (ref pr);
                    if (pr.is_empty ()) continue;
                    pr = pr.inflate (g.stroke_width + g.blur * 3 + 2);
                    r = any ? r.union (pr) : pr;
                    any = true;
                }
            }
            return r;
        }

        public static double total_width (TextLayout tl) {
            double w = 0;
            foreach (var g in tl.glyphs) w = double.max (w, g.x + g.advance);
            double mn = 0;
            foreach (var g in tl.glyphs) mn = double.min (mn, g.x);
            return w - mn;
        }

        public static void draw (TextLayout tl, PropGroup text, BezPath? path, double t, TextDocument d, LayerBuffer buf) {
            var to_px = Mat4.scaling (buf.scale, buf.scale, 1).multiply (Mat4.translation (-buf.x0, -buf.y0, 0));
            var po = text.group ("path-options");
            double tw = total_width (tl);
            foreach (var g in tl.glyphs) {
                if (g.paths.size == 0 || g.opacity <= 0) continue;
                var m = glyph_matrix (g, path, po, t, tw);
                var list = new Gee.ArrayList<BezPath> ();
                foreach (var p in g.paths) {
                    var c = p.copy ();
                    c.transform (m);
                    list.add (c);
                }
                double op = (g.opacity / 100.0).clamp (0, 1);
                FloatImage target = buf.img;
                if (g.blur > 0.3) target = new FloatImage (buf.img.width, buf.img.height);
                bool do_fill = d.apply_fill || g.fill != d.fill;
                bool do_stroke = (d.apply_stroke || g.stroke_width > 0) && g.stroke_width > 0;
                if (d.fill_over_stroke) {
                    if (do_stroke) stroke_glyph (target, list, to_px, g, buf, op);
                    if (do_fill) Raster.shade_solid (target, Raster.coverage (list, to_px, buf.img.width, buf.img.height), g.fill, op);
                } else {
                    if (do_fill) Raster.shade_solid (target, Raster.coverage (list, to_px, buf.img.width, buf.img.height), g.fill, op);
                    if (do_stroke) stroke_glyph (target, list, to_px, g, buf, op);
                }
                if (target != buf.img) {
                    Blur.gaussian (target, g.blur * buf.scale / 2, g.blur * buf.scale / 2);
                    Pixels.blend (buf.img, new CompImage (target, 0, 0), BlendMode.NORMAL, true, false);
                }
            }
        }

        private static void stroke_glyph (FloatImage target, Gee.List<BezPath> list, Mat4 to_px, TextGlyph g, LayerBuffer buf, double op) {
            var ss = new StrokeStyle ();
            ss.width = g.stroke_width;
            ss.join = Cairo.LineJoin.ROUND;
            Raster.shade_solid (target, Raster.stroke_coverage (list, to_px, buf.img.width, buf.img.height, ss), g.stroke, op);
        }
    }

    public class TextExpressionVars {
        public static bool active = false;
        public static int index = 0;
        public static int total = 0;
        public static double selector_value = 100;
    }
}
