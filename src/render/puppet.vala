using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class PuppetMesh {
        public double[] rx = {};
        public double[] ry = {};
        public int[] tris = {};
        public int vertex_count = 0;
    }

    namespace Puppet {
        public PropGroup pins_group (PropGroup fx) {
            var g = fx.group ("pins");
            if (g == null) {
                g = new PropGroup ("puppet.pins", "pins", _("Pins"));
                fx.add<PropGroup> (g);
            }
            return g;
        }

        public PropGroup add_pin (PropGroup fx, double x, double y, bool starch = false) {
            var pins = pins_group (fx);
            var pin = new PropGroup ("puppet.pin", pins.unique_key ("pin"), starch ? _("Starch %d").printf (pins.children.size + 1) : _("Puppet Pin %d").printf (pins.children.size + 1));
            pin.attrs["rest-x"] = BezPath.fmt (x);
            pin.attrs["rest-y"] = BezPath.fmt (y);
            pin.attrs["kind"] = starch ? "starch" : "deform";
            pin.add<Property> (Factory.point ("position", _("Position"), { x, y }));
            if (starch) pin.add<Property> (Factory.scalar ("amount", _("Amount"), 50).range (0, 100));
            pins.add<PropGroup> (pin);
            fx.touch ();
            return pin;
        }

        public Gee.ArrayList<PropGroup> pins (PropGroup fx) {
            var r = new Gee.ArrayList<PropGroup> ();
            var g = fx.group ("pins");
            if (g == null) return r;
            foreach (var c in g.children) {
                var p = c as PropGroup;
                if (p != null && p.type == "puppet.pin") r.add (p);
            }
            return r;
        }

        public PuppetMesh build_mesh (LayerBuffer buf, int triangles, double expansion_units) {
            var img = buf.img;
            int w = img.width, h = img.height;
            int opaque = 0;
            for (size_t i = 0; i < img.pixel_count (); i++) if (img.data[i * 4 + 3] > 0.01f) opaque++;
            var mesh = new PuppetMesh ();
            if (opaque == 0) return mesh;
            double step = double.max (2, Math.sqrt ((double) opaque / double.max (2, triangles / 2.0)));
            int cols = int.max (1, (int) Math.ceil (w / step)), rows = int.max (1, (int) Math.ceil (h / step));
            double exp_px = expansion_units * buf.scale;
            var used = new bool[(cols + 1) * (rows + 1)];
            var cell_on = new bool[cols * rows];
            for (int r = 0; r < rows; r++)
                for (int c = 0; c < cols; c++) {
                    int x0 = (int) Math.floor (c * step - exp_px), x1 = (int) Math.ceil ((c + 1) * step + exp_px);
                    int y0 = (int) Math.floor (r * step - exp_px), y1 = (int) Math.ceil ((r + 1) * step + exp_px);
                    bool on = false;
                    for (int y = int.max (0, y0); y < int.min (h, y1) && !on; y += 1)
                        for (int x = int.max (0, x0); x < int.min (w, x1); x += 1)
                            if (img.data[img.offset (x, y) + 3] > 0.01f) {
                                on = true;
                                break;
                            }
                    cell_on[r * cols + c] = on;
                    if (on) {
                        used[r * (cols + 1) + c] = true;
                        used[r * (cols + 1) + c + 1] = true;
                        used[(r + 1) * (cols + 1) + c] = true;
                        used[(r + 1) * (cols + 1) + c + 1] = true;
                    }
                }
            double[] vrx = {}, vry = {};
            int[] vtris = {};
            var index = new int[(cols + 1) * (rows + 1)];
            for (int r = 0; r <= rows; r++)
                for (int c = 0; c <= cols; c++) {
                    int k = r * (cols + 1) + c;
                    index[k] = -1;
                    if (!used[k]) continue;
                    double lx, ly;
                    buf.to_layer (double.min (c * step, w), double.min (r * step, h), out lx, out ly);
                    index[k] = mesh.vertex_count++;
                    vrx += lx;
                    vry += ly;
                }
            for (int r = 0; r < rows; r++)
                for (int c = 0; c < cols; c++) {
                    if (!cell_on[r * cols + c]) continue;
                    int a = index[r * (cols + 1) + c], b = index[r * (cols + 1) + c + 1];
                    int d = index[(r + 1) * (cols + 1) + c], e = index[(r + 1) * (cols + 1) + c + 1];
                    vtris += a;
                    vtris += b;
                    vtris += e;
                    vtris += a;
                    vtris += e;
                    vtris += d;
                }
            mesh.rx = vrx;
            mesh.ry = vry;
            mesh.tris = vtris;
            return mesh;
        }

        public void deform_point (double vx, double vy, double[] px, double[] py, double[] qx, double[] qy, double[] wk, out double ox, out double oy) {
            int n = px.length;
            if (n == 0) {
                ox = vx;
                oy = vy;
                return;
            }
            double sw = 0, psx = 0, psy = 0, qsx = 0, qsy = 0;
            var w = new double[n];
            for (int i = 0; i < n; i++) {
                double d2 = (px[i] - vx) * (px[i] - vx) + (py[i] - vy) * (py[i] - vy);
                if (d2 < 1e-12) {
                    ox = qx[i];
                    oy = qy[i];
                    return;
                }
                w[i] = wk[i] / d2;
                sw += w[i];
                psx += w[i] * px[i];
                psy += w[i] * py[i];
                qsx += w[i] * qx[i];
                qsy += w[i] * qy[i];
            }
            psx /= sw;
            psy /= sw;
            qsx /= sw;
            qsy /= sw;
            double sr = 0, si = 0;
            for (int i = 0; i < n; i++) {
                double ax = px[i] - psx, ay = py[i] - psy, bx = qx[i] - qsx, by = qy[i] - qsy;
                sr += w[i] * (bx * ax + by * ay);
                si += w[i] * (by * ax - bx * ay);
            }
            double mag = Math.hypot (sr, si);
            double cr = 1, ci = 0;
            if (mag > 1e-12) {
                cr = sr / mag;
                ci = si / mag;
            }
            double dx = vx - psx, dy = vy - psy;
            ox = qsx + dx * cr - dy * ci;
            oy = qsy + dx * ci + dy * cr;
        }

        public void raster_triangle (FloatImage src, FloatImage dst, double[] d, double[] s) {
            double minx = double.min (d[0], double.min (d[2], d[4])), maxx = double.max (d[0], double.max (d[2], d[4]));
            double miny = double.min (d[1], double.min (d[3], d[5])), maxy = double.max (d[1], double.max (d[3], d[5]));
            int x0 = int.max (0, (int) Math.floor (minx)), x1 = int.min (dst.width - 1, (int) Math.ceil (maxx));
            int y0 = int.max (0, (int) Math.floor (miny)), y1 = int.min (dst.height - 1, (int) Math.ceil (maxy));
            double den = (d[3] - d[5]) * (d[0] - d[4]) + (d[4] - d[2]) * (d[1] - d[5]);
            if (den.abs () < 1e-12) return;
            for (int y = y0; y <= y1; y++)
                for (int x = x0; x <= x1; x++) {
                    double px = x + 0.5, py = y + 0.5;
                    double l0 = ((d[3] - d[5]) * (px - d[4]) + (d[4] - d[2]) * (py - d[5])) / den;
                    double l1 = ((d[5] - d[1]) * (px - d[4]) + (d[0] - d[4]) * (py - d[5])) / den;
                    double l2 = 1 - l0 - l1;
                    if (l0 < -1e-6 || l1 < -1e-6 || l2 < -1e-6) continue;
                    double sx = l0 * s[0] + l1 * s[2] + l2 * s[4], sy = l0 * s[1] + l1 * s[3] + l2 * s[5];
                    float r, g, b, a;
                    Pixels.sample_premul (src, sx, sy, out r, out g, out b, out a);
                    size_t o = dst.offset (x, y);
                    dst.data[o] = r;
                    dst.data[o + 1] = g;
                    dst.data[o + 2] = b;
                    dst.data[o + 3] = a;
                }
        }

        public double max_displacement (PropGroup fx, double t) {
            double m = 0;
            foreach (var pin in pins (fx)) {
                var p = pin.vec ("position", t);
                double rx = double.parse (pin.attr ("rest-x", "0")), ry = double.parse (pin.attr ("rest-y", "0"));
                m = double.max (m, Math.hypot (p[0] - rx, p[1] - ry));
            }
            return m;
        }

        public void register () {
            EffectRegistry.add (new EffectDef ("puppet", _("Puppet"), _("Distort"), (g) => {
                g.add<Property> (Factory.scalar ("expansion", _("Expansion"), 3).range (-100, 100).ui_range (0, 20));
                g.add<Property> (Factory.scalar ("triangles", _("Triangles"), 350).range (10, 5000).ui_range (20, 2000));
                g.add<PropGroup> (new PropGroup ("puppet.pins", "pins", _("Pins")));
            }, (ctx, fx, t) => {
                var plist = pins (fx);
                if (plist.size == 0) return;
                double[] px = {}, py = {}, qx = {}, qy = {}, wk = {};
                foreach (var pin in plist) {
                    var p = pin.vec ("position", t);
                    px += double.parse (pin.attr ("rest-x", "0"));
                    py += double.parse (pin.attr ("rest-y", "0"));
                    bool starch = pin.attr ("kind", "deform") == "starch";
                    qx += starch ? px[px.length - 1] : p[0];
                    qy += starch ? py[py.length - 1] : p[1];
                    wk += starch ? 0.2 + pin.num ("amount", t) / 50.0 : 1.0;
                }
                var mesh = build_mesh (ctx.buf, (int) fx.num ("triangles", t), fx.num ("expansion", t));
                if (mesh.vertex_count == 0) return;
                var dx = new double[mesh.vertex_count];
                var dy = new double[mesh.vertex_count];
                for (int i = 0; i < mesh.vertex_count; i++) deform_point (mesh.rx[i], mesh.ry[i], px, py, qx, qy, wk, out dx[i], out dy[i]);
                var src = ctx.buf.img;
                var dst = new FloatImage (src.width, src.height);
                for (int k = 0; k + 2 < mesh.tris.length; k += 3) {
                    var dd = new double[6];
                    var ss = new double[6];
                    for (int j = 0; j < 3; j++) {
                        int vi = mesh.tris[k + j];
                        ctx.buf.to_pixel (dx[vi], dy[vi], out dd[j * 2], out dd[j * 2 + 1]);
                        ctx.buf.to_pixel (mesh.rx[vi], mesh.ry[vi], out ss[j * 2], out ss[j * 2 + 1]);
                    }
                    raster_triangle (src, dst, dd, ss);
                }
                ctx.buf.img = dst;
            }, (fx, t) => max_displacement (fx, t)));
        }
    }
}
