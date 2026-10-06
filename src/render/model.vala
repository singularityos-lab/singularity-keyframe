using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class ModelMesh {
        public double[] pos = {};
        public double[] nrm = {};
        public double[] uv = {};
        public int[] idx = {};
        public double[] color = { 0.8, 0.8, 0.8, 1 };
        public FloatImage? texture = null;
        public bool double_sided = true;
    }

    public class Model3D {
        public Gee.ArrayList<ModelMesh> meshes = new Gee.ArrayList<ModelMesh> ();
        public double min_x = 0;
        public double min_y = 0;
        public double min_z = 0;
        public double max_x = 0;
        public double max_y = 0;
        public double max_z = 0;

        public int triangle_count () {
            int n = 0;
            foreach (var m in meshes) n += m.idx.length / 3;
            return n;
        }
    }

    public errordomain ModelError {
        FORMAT,
        UNSUPPORTED
    }

    namespace Gltf {
        public const uint32 GLB_MAGIC = 0x46546C67;
        public const uint32 CHUNK_JSON = 0x4E4F534A;
        public const uint32 CHUNK_BIN = 0x004E4942;

        private uint32 u32 (uint8[] d, size_t p) {
            return d[p] | ((uint32) d[p + 1] << 8) | ((uint32) d[p + 2] << 16) | ((uint32) d[p + 3] << 24);
        }

        public Model3D load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            return parse (data, Path.get_dirname (path));
        }

        public Model3D parse (uint8[] data, string base_dir) throws Error {
            string json_text = "";
            Bytes? glb_bin = null;
            if (data.length >= 12 && u32 (data, 0) == GLB_MAGIC) {
                uint32 total = u32 (data, 8);
                if (total > data.length) throw new ModelError.FORMAT ("The GLB file is truncated");
                size_t pos = 12;
                while (pos + 8 <= total) {
                    uint32 len = u32 (data, pos);
                    uint32 type = u32 (data, pos + 4);
                    size_t start = pos + 8;
                    if (start + len > total) throw new ModelError.FORMAT ("Bad GLB chunk");
                    if (type == CHUNK_JSON) {
                        var sb = new StringBuilder.sized (len + 1);
                        sb.append_len ((string) ((uint8*) data + start), len);
                        json_text = sb.str;
                    } else if (type == CHUNK_BIN) {
                        glb_bin = new Bytes (data[start:start + len]);
                    }
                    pos = start + len;
                }
            } else {
                var sb = new StringBuilder.sized (data.length + 1);
                sb.append_len ((string) data, data.length);
                json_text = sb.str;
            }
            var parser = new Json.Parser ();
            parser.load_from_data (json_text);
            var root = parser.get_root ().get_object ();
            var buffers = new Gee.ArrayList<Bytes> ();
            if (root.has_member ("buffers")) {
                foreach (var bn in root.get_array_member ("buffers").get_elements ()) {
                    var bo = bn.get_object ();
                    if (bo.has_member ("uri")) {
                        buffers.add (read_uri (bo.get_string_member ("uri"), base_dir));
                    } else if (glb_bin != null) {
                        buffers.add (glb_bin);
                    } else {
                        throw new ModelError.FORMAT ("A buffer has no data");
                    }
                }
            }
            var model = new Model3D ();
            var views = root.has_member ("bufferViews") ? root.get_array_member ("bufferViews") : new Json.Array ();
            var accs = root.has_member ("accessors") ? root.get_array_member ("accessors") : new Json.Array ();
            var mats = root.has_member ("materials") ? root.get_array_member ("materials") : new Json.Array ();
            var textures = root.has_member ("textures") ? root.get_array_member ("textures") : new Json.Array ();
            var images = root.has_member ("images") ? root.get_array_member ("images") : new Json.Array ();
            if (!root.has_member ("meshes")) return model;
            var meshes = root.get_array_member ("meshes");
            var nodes = root.has_member ("nodes") ? root.get_array_member ("nodes") : new Json.Array ();
            var roots = new Gee.ArrayList<int> ();
            if (root.has_member ("scenes") && root.get_array_member ("scenes").get_length () > 0) {
                int scene = root.has_member ("scene") ? (int) root.get_int_member ("scene") : 0;
                var so = root.get_array_member ("scenes").get_object_element (scene);
                if (so.has_member ("nodes")) foreach (var n in so.get_array_member ("nodes").get_elements ()) roots.add ((int) n.get_int ());
            } else {
                var is_child = new bool[nodes.get_length ()];
                for (uint i = 0; i < nodes.get_length (); i++) {
                    var no = nodes.get_object_element (i);
                    if (no.has_member ("children")) foreach (var c in no.get_array_member ("children").get_elements ()) is_child[c.get_int ()] = true;
                }
                for (int i = 0; i < is_child.length; i++) if (!is_child[i]) roots.add (i);
            }
            if (nodes.get_length () == 0) {
                for (uint mi = 0; mi < meshes.get_length (); mi++) add_mesh (model, meshes.get_object_element (mi), new Mat4 (), accs, views, buffers, mats, textures, images, base_dir);
            } else {
                foreach (var r in roots) visit (model, nodes, r, new Mat4 (), meshes, accs, views, buffers, mats, textures, images, base_dir, 0);
            }
            bool first = true;
            foreach (var m in model.meshes)
                for (int i = 0; i + 2 < m.pos.length; i += 3) {
                    if (first) {
                        model.min_x = model.max_x = m.pos[i];
                        model.min_y = model.max_y = m.pos[i + 1];
                        model.min_z = model.max_z = m.pos[i + 2];
                        first = false;
                    }
                    model.min_x = double.min (model.min_x, m.pos[i]);
                    model.max_x = double.max (model.max_x, m.pos[i]);
                    model.min_y = double.min (model.min_y, m.pos[i + 1]);
                    model.max_y = double.max (model.max_y, m.pos[i + 1]);
                    model.min_z = double.min (model.min_z, m.pos[i + 2]);
                    model.max_z = double.max (model.max_z, m.pos[i + 2]);
                }
            return model;
        }

        private Bytes read_uri (string uri, string base_dir) throws Error {
            if (uri.has_prefix ("data:")) {
                int comma = uri.index_of (",");
                return new Bytes (Base64.decode (uri.substring (comma + 1)));
            }
            uint8[] ext;
            FileUtils.get_data (Path.build_filename (base_dir, Uri.unescape_string (uri) ?? uri), out ext);
            return new Bytes (ext);
        }

        private Mat4 node_matrix (Json.Object node) {
            if (node.has_member ("matrix")) {
                var a = node.get_array_member ("matrix");
                var m = new Mat4 ();
                for (int c = 0; c < 4; c++)
                    for (int r = 0; r < 4; r++) m.m[r * 4 + c] = a.get_double_element (c * 4 + r);
                return m;
            }
            var m = new Mat4 ();
            if (node.has_member ("translation")) {
                var a = node.get_array_member ("translation");
                m = m.multiply (Mat4.translation (a.get_double_element (0), a.get_double_element (1), a.get_double_element (2)));
            }
            if (node.has_member ("rotation")) {
                var a = node.get_array_member ("rotation");
                double x = a.get_double_element (0), y = a.get_double_element (1), z = a.get_double_element (2), w = a.get_double_element (3);
                var r = new Mat4 ();
                r.m[0] = 1 - 2 * (y * y + z * z);
                r.m[1] = 2 * (x * y - z * w);
                r.m[2] = 2 * (x * z + y * w);
                r.m[4] = 2 * (x * y + z * w);
                r.m[5] = 1 - 2 * (x * x + z * z);
                r.m[6] = 2 * (y * z - x * w);
                r.m[8] = 2 * (x * z - y * w);
                r.m[9] = 2 * (y * z + x * w);
                r.m[10] = 1 - 2 * (x * x + y * y);
                m = m.multiply (r);
            }
            if (node.has_member ("scale")) {
                var a = node.get_array_member ("scale");
                m = m.multiply (Mat4.scaling (a.get_double_element (0), a.get_double_element (1), a.get_double_element (2)));
            }
            return m;
        }

        private void visit (Model3D model, Json.Array nodes, int index, Mat4 parent, Json.Array meshes, Json.Array accs, Json.Array views, Gee.List<Bytes> buffers,
                            Json.Array mats, Json.Array textures, Json.Array images, string base_dir, int depth) throws Error {
            if (depth > 64 || index < 0 || index >= nodes.get_length ()) return;
            var node = nodes.get_object_element (index);
            var m = parent.multiply (node_matrix (node));
            if (node.has_member ("mesh")) add_mesh (model, meshes.get_object_element ((uint) node.get_int_member ("mesh")), m, accs, views, buffers, mats, textures, images, base_dir);
            if (node.has_member ("children"))
                foreach (var c in node.get_array_member ("children").get_elements ()) visit (model, nodes, (int) c.get_int (), m, meshes, accs, views, buffers, mats, textures, images, base_dir, depth + 1);
        }

        private void add_mesh (Model3D model, Json.Object mo, Mat4 m, Json.Array accs, Json.Array views, Gee.List<Bytes> buffers, Json.Array mats,
                               Json.Array textures, Json.Array images, string base_dir) throws Error {
            foreach (var pn in mo.get_array_member ("primitives").get_elements ()) {
                var po = pn.get_object ();
                if (po.has_member ("mode") && po.get_int_member ("mode") != 4) continue;
                var attrs = po.get_object_member ("attributes");
                if (!attrs.has_member ("POSITION")) continue;
                var mesh = new ModelMesh ();
                var p = read_floats (accs, views, buffers, (int) attrs.get_int_member ("POSITION"), 3);
                var tp = new double[p.length];
                for (int i = 0; i + 2 < p.length; i += 3) {
                    var v = m.transform_point (Vec3 (p[i], p[i + 1], p[i + 2]));
                    tp[i] = v.x;
                    tp[i + 1] = -v.y;
                    tp[i + 2] = -v.z;
                }
                mesh.pos = tp;
                if (attrs.has_member ("NORMAL")) {
                    var n = read_floats (accs, views, buffers, (int) attrs.get_int_member ("NORMAL"), 3);
                    var tn = new double[n.length];
                    for (int i = 0; i + 2 < n.length; i += 3) {
                        var v = m.transform_vector (Vec3 (n[i], n[i + 1], n[i + 2])).normalized ();
                        tn[i] = v.x;
                        tn[i + 1] = -v.y;
                        tn[i + 2] = -v.z;
                    }
                    mesh.nrm = tn;
                }
                if (attrs.has_member ("TEXCOORD_0")) mesh.uv = read_floats (accs, views, buffers, (int) attrs.get_int_member ("TEXCOORD_0"), 2);
                if (po.has_member ("indices")) mesh.idx = read_ints (accs, views, buffers, (int) po.get_int_member ("indices"));
                else {
                    var ix = new int[tp.length / 3];
                    for (int i = 0; i < ix.length; i++) ix[i] = i;
                    mesh.idx = ix;
                }
                if (po.has_member ("material") && po.get_int_member ("material") < mats.get_length ()) {
                    var mat = mats.get_object_element ((uint) po.get_int_member ("material"));
                    if (mat.has_member ("doubleSided")) mesh.double_sided = mat.get_boolean_member ("doubleSided");
                    if (mat.has_member ("pbrMetallicRoughness")) {
                        var pbr = mat.get_object_member ("pbrMetallicRoughness");
                        if (pbr.has_member ("baseColorFactor")) {
                            var c = pbr.get_array_member ("baseColorFactor");
                            mesh.color = { c.get_double_element (0), c.get_double_element (1), c.get_double_element (2), c.get_length () > 3 ? c.get_double_element (3) : 1 };
                        }
                        if (pbr.has_member ("baseColorTexture")) {
                            int ti = (int) pbr.get_object_member ("baseColorTexture").get_int_member ("index");
                            mesh.texture = load_texture (ti, textures, images, views, buffers, base_dir);
                        }
                    }
                }
                if (mesh.nrm.length != mesh.pos.length) mesh.nrm = flat_normals (mesh);
                model.meshes.add (mesh);
            }
        }

        private FloatImage? load_texture (int ti, Json.Array textures, Json.Array images, Json.Array views, Gee.List<Bytes> buffers, string base_dir) {
            try {
                if (ti < 0 || ti >= textures.get_length ()) return null;
                var to = textures.get_object_element (ti);
                if (!to.has_member ("source")) return null;
                var io = images.get_object_element ((uint) to.get_int_member ("source"));
                Bytes bytes;
                if (io.has_member ("uri")) bytes = read_uri (io.get_string_member ("uri"), base_dir);
                else {
                    int stride;
                    bytes = new Bytes (view_data (views, buffers, (int) io.get_int_member ("bufferView"), out stride));
                }
                var tex = Gdk.Texture.from_bytes (bytes);
                var img = FloatImage.from_texture (tex, true);
                Pixels.premultiply (img);
                return img;
            } catch (Error e) {
                return null;
            }
        }

        private double[] flat_normals (ModelMesh m) {
            var acc = new double[m.pos.length];
            for (int k = 0; k + 2 < m.idx.length; k += 3) {
                int a = m.idx[k], b = m.idx[k + 1], c = m.idx[k + 2];
                int nv = m.pos.length / 3;
                if (a < 0 || b < 0 || c < 0 || a >= nv || b >= nv || c >= nv) continue;
                var pa = Vec3 (m.pos[a * 3], m.pos[a * 3 + 1], m.pos[a * 3 + 2]);
                var pb = Vec3 (m.pos[b * 3], m.pos[b * 3 + 1], m.pos[b * 3 + 2]);
                var pc = Vec3 (m.pos[c * 3], m.pos[c * 3 + 1], m.pos[c * 3 + 2]);
                var n = pb.sub (pa).cross (pc.sub (pa));
                foreach (int v in new int[] { a, b, c }) {
                    acc[v * 3] += n.x;
                    acc[v * 3 + 1] += n.y;
                    acc[v * 3 + 2] += n.z;
                }
            }
            for (int i = 0; i + 2 < acc.length; i += 3) {
                var n = Vec3 (acc[i], acc[i + 1], acc[i + 2]).normalized ();
                acc[i] = n.x;
                acc[i + 1] = n.y;
                acc[i + 2] = n.z;
            }
            return acc;
        }

        private uint8[] view_data (Json.Array views, Gee.List<Bytes> buffers, int view, out int stride) throws Error {
            var vo = views.get_object_element (view);
            int buffer = (int) vo.get_int_member ("buffer");
            int off = vo.has_member ("byteOffset") ? (int) vo.get_int_member ("byteOffset") : 0;
            int len = (int) vo.get_int_member ("byteLength");
            stride = vo.has_member ("byteStride") ? (int) vo.get_int_member ("byteStride") : 0;
            unowned uint8[] all = buffers[buffer].get_data ();
            if (off + len > all.length) throw new ModelError.FORMAT ("Buffer view out of range");
            return all[off:off + len];
        }

        private double[] read_floats (Json.Array accs, Json.Array views, Gee.List<Bytes> buffers, int acc, int comps) throws Error {
            var ao = accs.get_object_element (acc);
            int count = (int) ao.get_int_member ("count");
            int ct = (int) ao.get_int_member ("componentType");
            bool normalized = ao.has_member ("normalized") && ao.get_boolean_member ("normalized");
            int size = ct == 5126 ? 4 : (ct == 5123 || ct == 5122 ? 2 : 1);
            int stride;
            var d = view_data (views, buffers, (int) ao.get_int_member ("bufferView"), out stride);
            int off = ao.has_member ("byteOffset") ? (int) ao.get_int_member ("byteOffset") : 0;
            if (stride == 0) stride = comps * size;
            var r = new double[count * comps];
            for (int i = 0; i < count; i++)
                for (int c = 0; c < comps; c++) {
                    size_t p = off + i * stride + c * size;
                    if (p + size > d.length) throw new ModelError.FORMAT ("Accessor out of range");
                    double v;
                    if (ct == 5126) {
                        uint32 bits = u32 (d, p);
                        float f = 0;
                        Memory.copy (&f, &bits, 4);
                        v = f;
                    } else if (size == 2) {
                        v = d[p] | (d[p + 1] << 8);
                        if (normalized) v /= 65535.0;
                    } else {
                        v = d[p];
                        if (normalized) v /= 255.0;
                    }
                    r[i * comps + c] = v;
                }
            return r;
        }

        private int[] read_ints (Json.Array accs, Json.Array views, Gee.List<Bytes> buffers, int acc) throws Error {
            var ao = accs.get_object_element (acc);
            int count = (int) ao.get_int_member ("count");
            int type = (int) ao.get_int_member ("componentType");
            int stride;
            var d = view_data (views, buffers, (int) ao.get_int_member ("bufferView"), out stride);
            int off = ao.has_member ("byteOffset") ? (int) ao.get_int_member ("byteOffset") : 0;
            int size = type == 5125 ? 4 : (type == 5123 ? 2 : 1);
            if (stride == 0) stride = size;
            var r = new int[count];
            for (int i = 0; i < count; i++) {
                size_t p = off + i * stride;
                if (p + size > d.length) throw new ModelError.FORMAT ("Index accessor out of range");
                if (size == 4) r[i] = (int) u32 (d, p);
                else if (size == 2) r[i] = d[p] | (d[p + 1] << 8);
                else r[i] = d[p];
            }
            return r;
        }
    }

    namespace ModelRender {
        public const double UNITS_PER_METER = 100.0;
        private Gee.HashMap<string, Model3D>? models = null;
        private Mutex models_mutex;
        public string? last_error;

        public Model3D? model_for (string path) {
            models_mutex.lock ();
            if (models == null) models = new Gee.HashMap<string, Model3D> ();
            var m = models[path];
            models_mutex.unlock ();
            if (m != null) return m;
            try {
                m = Gltf.load (path);
            } catch (Error e) {
                last_error = e.message;
                return null;
            }
            models_mutex.lock ();
            models[path] = m;
            models_mutex.unlock ();
            return m;
        }

        public void forget (string path) {
            models_mutex.lock ();
            if (models != null) models.unset (path);
            models_mutex.unlock ();
        }

        public CompImage? render (Renderer r, Layer l, double t, RenderSettings s, CameraInfo cam, Gee.List<LightInfo> lights) {
            var f = r.project.footage_by_id (l.source_id);
            if (f == null) return null;
            var model = model_for (f.effective_path ());
            if (model == null || model.meshes.size == 0) return null;
            var comp = l.comp;
            int cw = r.canvas_width (comp, s), ch = r.canvas_height (comp, s);
            double lt = l.layer_time (t);
            var mg = l.root.group ("model");
            double msc = (mg != null ? mg.vec ("model-scale", lt)[0] : 100) / 100.0 * UNITS_PER_METER;
            var tint = mg != null ? mg.vec ("tint", lt) : new double[] { 1, 1, 1, 1 };
            bool flat = mg != null && mg.choice ("shading", lt) == 1;
            var world = l.world_matrix (t).multiply (Mat4.scaling (msc, msc, msc));
            var view_proj = r.canvas_projective (s).multiply (r.projection (comp, cam)).multiply (cam.view);
            var mvp = view_proj.multiply (world);
            var mat = l.root.group ("material");
            bool lit = !flat && lights.size > 0 && (mat == null || mat.toggle ("accepts-lights", lt));
            double amb_k = mat != null ? mat.num ("ambient", lt) / 100.0 : 1;
            double dif_k = mat != null ? mat.num ("diffuse", lt) / 100.0 : 0.5;
            double spec_k = mat != null ? mat.num ("specular", lt) / 100.0 : 0.5;
            double shin = mat != null ? 1 + mat.num ("shininess", lt) * 2 : 11;
            var color = new FloatImage (cw, ch);
            var depth = new float[(size_t) cw * ch];
            for (size_t i = 0; i < depth.length; i++) depth[i] = float.MAX;
            int x0 = cw, y0 = ch, x1 = -1, y1 = -1;
            foreach (var mesh in model.meshes) {
                int nv = mesh.pos.length / 3;
                var sx = new double[nv];
                var sy = new double[nv];
                var sw = new double[nv];
                var wx = new double[nv];
                var wy = new double[nv];
                var wz = new double[nv];
                var nx = new double[nv];
                var ny = new double[nv];
                var nz = new double[nv];
                for (int i = 0; i < nv; i++) {
                    var lp = Vec3 (mesh.pos[i * 3], mesh.pos[i * 3 + 1], mesh.pos[i * 3 + 2]);
                    double X = mvp.m[0] * lp.x + mvp.m[1] * lp.y + mvp.m[2] * lp.z + mvp.m[3];
                    double Y = mvp.m[4] * lp.x + mvp.m[5] * lp.y + mvp.m[6] * lp.z + mvp.m[7];
                    double W = mvp.m[12] * lp.x + mvp.m[13] * lp.y + mvp.m[14] * lp.z + mvp.m[15];
                    sw[i] = W;
                    sx[i] = W > 1e-6 ? X / W : 0;
                    sy[i] = W > 1e-6 ? Y / W : 0;
                    var wp = world.transform_point (lp);
                    wx[i] = wp.x;
                    wy[i] = wp.y;
                    wz[i] = wp.z;
                    var wn = world.transform_vector (Vec3 (mesh.nrm[i * 3], mesh.nrm[i * 3 + 1], mesh.nrm[i * 3 + 2])).normalized ();
                    nx[i] = wn.x;
                    ny[i] = wn.y;
                    nz[i] = wn.z;
                }
                for (int k = 0; k + 2 < mesh.idx.length; k += 3) {
                    int a = mesh.idx[k], b = mesh.idx[k + 1], c = mesh.idx[k + 2];
                    if (a >= nv || b >= nv || c >= nv) continue;
                    if (sw[a] <= 1 || sw[b] <= 1 || sw[c] <= 1) continue;
                    double area = (sx[b] - sx[a]) * (sy[c] - sy[a]) - (sx[c] - sx[a]) * (sy[b] - sy[a]);
                    if (area.abs () < 1e-9) continue;
                    if (!mesh.double_sided && area > 0) continue;
                    int bx0 = int.max (0, (int) Math.floor (double.min (sx[a], double.min (sx[b], sx[c]))));
                    int bx1 = int.min (cw - 1, (int) Math.ceil (double.max (sx[a], double.max (sx[b], sx[c]))));
                    int by0 = int.max (0, (int) Math.floor (double.min (sy[a], double.min (sy[b], sy[c]))));
                    int by1 = int.min (ch - 1, (int) Math.ceil (double.max (sy[a], double.max (sy[b], sy[c]))));
                    for (int y = by0; y <= by1; y++)
                        for (int x = bx0; x <= bx1; x++) {
                            double px = x + 0.5, py = y + 0.5;
                            double l0 = ((sx[b] - px) * (sy[c] - py) - (sx[c] - px) * (sy[b] - py)) / area;
                            double l1 = ((sx[c] - px) * (sy[a] - py) - (sx[a] - px) * (sy[c] - py)) / area;
                            double l2 = 1 - l0 - l1;
                            if (l0 < -1e-9 || l1 < -1e-9 || l2 < -1e-9) continue;
                            double ia = l0 / sw[a], ib = l1 / sw[b], ic = l2 / sw[c];
                            double inv = ia + ib + ic;
                            double ka = ia / inv, kb = ib / inv, kc = ic / inv;
                            float z = (float) (1.0 / inv);
                            size_t di = (size_t) y * cw + x;
                            if (z >= depth[di]) continue;
                            double r0 = mesh.color[0], g0 = mesh.color[1], b0 = mesh.color[2], al = mesh.color[3];
                            if (mesh.texture != null && mesh.uv.length >= nv * 2) {
                                double u = ka * mesh.uv[a * 2] + kb * mesh.uv[b * 2] + kc * mesh.uv[c * 2];
                                double v = ka * mesh.uv[a * 2 + 1] + kb * mesh.uv[b * 2 + 1] + kc * mesh.uv[c * 2 + 1];
                                u -= Math.floor (u);
                                v -= Math.floor (v);
                                float tr, tg, tb, ta;
                                Pixels.sample_premul (mesh.texture, u * mesh.texture.width, v * mesh.texture.height, out tr, out tg, out tb, out ta);
                                if (ta > 1e-6f) {
                                    r0 *= tr / ta;
                                    g0 *= tg / ta;
                                    b0 *= tb / ta;
                                }
                                al *= ta;
                            }
                            r0 *= tint[0];
                            g0 *= tint[1];
                            b0 *= tint[2];
                            if (!flat) {
                                var n = Vec3 (ka * nx[a] + kb * nx[b] + kc * nx[c], ka * ny[a] + kb * ny[b] + kc * ny[c], ka * nz[a] + kb * nz[b] + kc * nz[c]).normalized ();
                                var wp = Vec3 (ka * wx[a] + kb * wx[b] + kc * wx[c], ka * wy[a] + kb * wy[b] + kc * wy[c], ka * wz[a] + kb * wz[b] + kc * wz[c]);
                                if (lit) {
                                    double srr, sgg, sbb, spr, spg, spb;
                                    r.shade (wp, n, cam.position, lights, amb_k, dif_k, spec_k, shin, out srr, out sgg, out sbb, out spr, out spg, out spb);
                                    r0 = r0 * srr + spr;
                                    g0 = g0 * sgg + spg;
                                    b0 = b0 * sbb + spb;
                                } else {
                                    var to_cam = cam.position.sub (wp).normalized ();
                                    double k2 = 0.35 + 0.65 * n.dot (to_cam).abs ();
                                    r0 *= k2;
                                    g0 *= k2;
                                    b0 *= k2;
                                }
                            }
                            depth[di] = z;
                            size_t o = color.offset (x, y);
                            color.data[o] = (float) (r0 * al);
                            color.data[o + 1] = (float) (g0 * al);
                            color.data[o + 2] = (float) (b0 * al);
                            color.data[o + 3] = (float) al;
                            x0 = int.min (x0, x);
                            y0 = int.min (y0, y);
                            x1 = int.max (x1, x);
                            y1 = int.max (y1, y);
                        }
                }
            }
            if (x1 < 0) return null;
            return new CompImage (color.cropped (x0, y0, x1 - x0 + 1, y1 - y0 + 1), x0, y0);
        }
    }
}
