using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    public class FramePrintSource : Singularity.Print.PageSource {
        private Singularity.Imaging.FloatImage frame;
        private Singularity.Print.PageFormat? format;

        public FramePrintSource (Singularity.Imaging.FloatImage frame, string title) {
            this.frame = frame;
            this.title = title;
            var x = new Singularity.Print.ExtraOptions (_("Frame"), _("How the frame is placed on the paper"));
            x.add_switch ("fill", _("Fill the Page"), null, false);
            extra_options = x;
        }

        public override async int paginate (Singularity.Print.PageFormat f) throws Error {
            format = f;
            page_width = f.width;
            page_height = f.height;
            return 1;
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (format == null) return;
            var px = Pixels.unpremultiplied (frame).to_rgba8 (true);
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, frame.width, frame.height);
            unowned uint8[] dst = surface.get_data ();
            int stride = surface.get_stride ();
            for (int y = 0; y < frame.height; y++)
                for (int x = 0; x < frame.width; x++) {
                    size_t s = ((size_t) y * frame.width + x) * 4;
                    int d = y * stride + x * 4;
                    uint a = px[s + 3];
                    dst[d] = (uint8) (px[s + 2] * a / 255);
                    dst[d + 1] = (uint8) (px[s + 1] * a / 255);
                    dst[d + 2] = (uint8) (px[s] * a / 255);
                    dst[d + 3] = (uint8) a;
                }
            surface.mark_dirty ();
            bool fill = extra_options.get_bool ("fill");
            double sx = format.content_width / frame.width, sy = format.content_height / frame.height;
            double sc = fill ? double.max (sx, sy) : double.min (sx, sy);
            cr.save ();
            cr.rectangle (format.margin_left, format.margin_top, format.content_width, format.content_height);
            cr.clip ();
            cr.translate (format.margin_left + (format.content_width - frame.width * sc) / 2, format.margin_top + (format.content_height - frame.height * sc) / 2);
            cr.scale (sc, sc);
            cr.set_source_surface (surface, 0, 0);
            cr.paint ();
            cr.restore ();
        }
    }

    namespace Exports {
        public Singularity.Imaging.FloatImage current_frame (KeyframeWindow w, bool with_background) {
            var r = new Renderer (w.doc.project);
            var s = new RenderSettings ();
            s.use_cache = false;
            var img = r.render (w.doc.comp, w.doc.time, s);
            r.media.close ();
            if (with_background) {
                var bg = w.doc.comp.background;
                var flat = new Singularity.Imaging.FloatImage.filled (img.width, img.height, (float) bg[0], (float) bg[1], (float) bg[2], 1);
                Pixels.blend (flat, new CompImage (img, 0, 0), Singularity.Imaging.BlendMode.NORMAL, true, false);
                return flat;
            }
            return img;
        }

        public void export_frame (KeyframeWindow w) {
            if (w.doc.comp == null) return;
            var dlg = new FileDialog ();
            dlg.title = _("Save Frame As");
            dlg.initial_name = "%s %s.png".printf (w.doc.comp.name, Timecode.format (w.doc.time, w.doc.comp.fps).replace (":", "-"));
            dlg.save.begin (w, null, (o, res) => {
                try {
                    var f = dlg.save.end (res);
                    if (f == null) return;
                    var path = f.get_path ();
                    var lower = path.down ();
                    var img = current_frame (w, lower.has_suffix (".jpg") || lower.has_suffix (".jpeg"));
                    if (lower.has_suffix (".exr")) FileUtils.set_data (path, Exr.encode (img, true, true));
                    else if (lower.has_suffix (".tif") || lower.has_suffix (".tiff")) FileUtils.set_data (path, Tiff.encode (img, 16, true, true));
                    else if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg")) ImageIO.save_pixbuf (img, path, "jpeg", 92, false);
                    else if (lower.has_suffix (".svg")) FrameSvg.save (w.doc, path);
                    else ImageIO.save_png (img, path.has_suffix (".png") ? path : path + ".png", 16, true);
                    w.toast (_("Frame saved"));
                } catch (Error e) {
                    w.toast (_("Could not save the frame: %s").printf (e.message));
                }
            });
        }

        public void print_frame (KeyframeWindow w) {
            if (w.doc.comp == null) return;
            var src = new FramePrintSource (current_frame (w, true), w.doc.comp.name);
            Singularity.Print.run_source.begin (w, src);
        }
    }

    namespace FrameSvg {
        public void save (Document doc, string path) throws Error {
            var comp = doc.comp;
            var surface = new Cairo.SvgSurface (path, comp.width, comp.height);
            var cr = new Cairo.Context (surface);
            cr.set_source_rgb (comp.background[0], comp.background[1], comp.background[2]);
            cr.paint ();
            for (int i = comp.layers.size - 1; i >= 0; i--) {
                var l = comp.layers[i];
                if (!comp.layer_visible (l, doc.time)) continue;
                double lt = l.layer_time (doc.time);
                double op = l.opacity_at (doc.time);
                cr.save ();
                cr.set_matrix (l.world_matrix (doc.time).to_cairo ());
                if (l.kind == LayerKind.SHAPE && l.contents != null) {
                    var sr = new ShapeRenderer (lt);
                    var scene = sr.build (l.contents, new Mat4 ());
                    for (int k = scene.ops.size - 1; k >= 0; k--) {
                        var dop = scene.ops[k];
                        var st = dop.style;
                        foreach (var p in dop.all_paths ()) p.to_cairo (cr);
                        var c = st.vec ("color", lt);
                        if (st.type.has_prefix ("shape.gradient")) {
                            var stops = st.vec ("stops", lt);
                            c = stops.length >= 5 ? new double[] { stops[1], stops[2], stops[3], stops[4] } : c;
                        }
                        double a = (c.length > 3 ? c[3] : 1) * st.num ("opacity", lt) / 100.0 * dop.opacity * op;
                        cr.set_source_rgba (c[0], c[1], c[2], a);
                        if (st.type == "shape.stroke" || st.type == "shape.gradient-stroke") {
                            cr.set_line_width (st.num ("width", lt));
                            cr.stroke ();
                        } else {
                            cr.set_fill_rule (st.attr ("rule", "nonzero") == "evenodd" ? Cairo.FillRule.EVEN_ODD : Cairo.FillRule.WINDING);
                            cr.fill ();
                        }
                    }
                } else if (l.kind == LayerKind.TEXT && l.text_group != null) {
                    var d = l.text_group.prop ("source-text").text_at (lt);
                    var tl = TextRenderer.layout_glyphs (d);
                    TextRenderer.apply_animators (l.text_group, tl, lt, l, d);
                    double tw = TextRenderer.total_width (tl);
                    foreach (var g in tl.glyphs) {
                        var m = TextRenderer.glyph_matrix (g, null, l.text_group.group ("path-options"), lt, tw);
                        foreach (var p in g.paths) {
                            var c = p.copy ();
                            c.transform (m);
                            c.to_cairo (cr);
                        }
                        cr.set_source_rgba (g.fill[0], g.fill[1], g.fill[2], (g.fill.length > 3 ? g.fill[3] : 1) * g.opacity / 100.0 * op);
                        cr.fill ();
                    }
                } else if (l.kind == LayerKind.SOLID && !l.adjustment) {
                    cr.rectangle (0, 0, l.solid_width, l.solid_height);
                    cr.set_source_rgba (l.solid_color[0], l.solid_color[1], l.solid_color[2], op);
                    cr.fill ();
                }
                cr.restore ();
            }
            surface.finish ();
        }
    }
}
