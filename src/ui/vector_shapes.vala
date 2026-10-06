namespace Singularity.Apps.Keyframe {

    namespace VectorShapes {
        private double[] color_of (string s, double fallback_alpha = 1) {
            Singularity.Apps.Draw.Rgba c;
            if (!Singularity.Apps.Draw.Colors.parse (s, out c)) return {};
            return { c.r, c.g, c.b, c.a * fallback_alpha };
        }

        private Gee.ArrayList<BezPath> paths_of (Singularity.Apps.Draw.PathData src) {
            var pd = new Singularity.Vector.PathData ();
            foreach (var s in src.segs) {
                switch (s.kind) {
                    case Singularity.Apps.Draw.SegKind.MOVE:
                        pd.move_to (s.x, s.y);
                        break;
                    case Singularity.Apps.Draw.SegKind.LINE:
                        pd.line_to (s.x, s.y);
                        break;
                    case Singularity.Apps.Draw.SegKind.CURVE:
                        pd.curve_to (s.x1, s.y1, s.x2, s.y2, s.x, s.y);
                        break;
                    default:
                        pd.close ();
                        break;
                }
            }
            return BezPath.from_path_data (pd);
        }

        private void add_item (PropGroup container, Singularity.Apps.Draw.Item item, Gee.List<TextDocumentPlacement> texts) {
            var grp = item as Singularity.Apps.Draw.Group;
            if (grp != null) {
                var g = Factory.shape_group (item.name != "" ? item.name : _("Group"));
                g.key = container.unique_key ("group");
                for (int i = grp.children.size - 1; i >= 0; i--) add_item (g.group ("contents"), grp.children[i], texts);
                container.add<PropGroup> (g);
                return;
            }
            var shape = item as Singularity.Apps.Draw.Shape;
            if (shape == null) return;
            var st = item.style;
            var g = Factory.shape_group (item.name != "" ? item.name : _("Shape"));
            g.key = container.unique_key ("group");
            var contents = g.group ("contents");
            foreach (var p in paths_of (shape.page_outline ())) {
                var ps = Factory.path_shape (p);
                ps.key = contents.unique_key ("path");
                contents.add<PropGroup> (ps);
            }
            var stroke = color_of (st.stroke);
            if (stroke.length == 4 && st.stroke_width > 0) {
                var sp = Factory.stroke (stroke, st.stroke_width);
                var dash = st.dash.pattern (st.stroke_width);
                if (dash.length >= 2) {
                    sp.prop ("dash").value = { dash[0] };
                    sp.prop ("gap").value = { dash[1] };
                }
                contents.add<PropGroup> (sp);
            }
            if (st.fill_kind == Singularity.Apps.Draw.FillKind.SOLID) {
                var fill = color_of (st.fill);
                if (fill.length == 4) contents.add<PropGroup> (Factory.fill (fill));
            } else if (st.fill_kind == Singularity.Apps.Draw.FillKind.LINEAR || st.fill_kind == Singularity.Apps.Draw.FillKind.RADIAL) {
                var a = color_of (st.fill);
                var b = color_of (st.fill2);
                if (a.length == 4 && b.length == 4) {
                    var gf = Factory.gradient_fill ();
                    gf.attrs["gradient"] = st.fill_kind == Singularity.Apps.Draw.FillKind.RADIAL ? "radial" : "linear";
                    gf.prop ("stops").value = { 0, a[0], a[1], a[2], a[3], 1, b[0], b[1], b[2], b[3] };
                    var bb = shape.bounds ();
                    double cx = bb.x + bb.w / 2, cy = bb.y + bb.h / 2;
                    double ang = st.gradient_angle * Math.PI / 180.0;
                    double r = double.max (bb.w, bb.h) / 2;
                    if (gf.attrs["gradient"] == "radial") {
                        gf.prop ("start").value = { cx, cy };
                        gf.prop ("end").value = { cx + r, cy };
                    } else {
                        gf.prop ("start").value = { cx - Math.cos (ang) * r, cy - Math.sin (ang) * r };
                        gf.prop ("end").value = { cx + Math.cos (ang) * r, cy + Math.sin (ang) * r };
                    }
                    contents.add<PropGroup> (gf);
                }
            }
            g.group ("transform").prop ("opacity").value = { st.opacity * 100 };
            container.add<PropGroup> (g);
            var text = item.display_text ();
            if (text.strip () != "") {
                var bb = shape.bounds ();
                var t = new TextDocumentPlacement ();
                t.text = text;
                t.x = bb.x + bb.w / 2;
                t.y = bb.y + bb.h / 2 + st.font_size * 0.35;
                t.size = st.font_size;
                t.family = st.font_family;
                t.bold = st.bold;
                t.italic = st.italic;
                t.color = color_of (st.text_color);
                texts.add (t);
            }
        }

        public class TextDocumentPlacement {
            public string text;
            public double x;
            public double y;
            public double size;
            public string family;
            public bool bold;
            public bool italic;
            public double[] color;
        }

        public Gee.ArrayList<Layer> layers_from_file (Composition comp, string path) throws Error {
            var doc = Singularity.Apps.Draw.Formats.load (path);
            var result = new Gee.ArrayList<Layer> ();
            if (doc.pages.size == 0) return result;
            var page = doc.pages[0];
            var layer = Factory.shape_layer (comp, Path.get_basename (path));
            double ox = (comp.width - page.width) / 2, oy = (comp.height - page.height) / 2;
            layer.transform.prop ("position").value = { ox, oy, 0 };
            var texts = new Gee.ArrayList<TextDocumentPlacement> ();
            for (int i = page.items.size - 1; i >= 0; i--) add_item (layer.contents, page.items[i], texts);
            result.add (layer);
            foreach (var t in texts) {
                var tl = Factory.text_layer (comp, t.text);
                var d = tl.text_group.prop ("source-text").text;
                d.size = t.size;
                d.font = t.family;
                d.weight = t.bold ? 700 : 400;
                d.italic = t.italic;
                if (t.color.length == 4) d.fill = t.color;
                tl.transform.prop ("position").value = { ox + t.x, oy + t.y, 0 };
                result.insert (0, tl);
            }
            return result;
        }
    }
}
