using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class ParticleState {
        public double[] x = {};
        public double[] y = {};
        public double[] vx = {};
        public double[] vy = {};
        public double[] age = {};
        public double[] life = {};
        public int[] id = {};
        public int count = 0;
        public int emitted = 0;
        public double emit_acc = 0;
        public double time = 0;

        public ParticleState copy () {
            var s = new ParticleState ();
            s.x = x[0:count];
            s.y = y[0:count];
            s.vx = vx[0:count];
            s.vy = vy[0:count];
            s.age = age[0:count];
            s.life = life[0:count];
            s.id = id[0:count];
            s.count = count;
            s.emitted = emitted;
            s.emit_acc = emit_acc;
            s.time = time;
            return s;
        }

        public void push (double px, double py, double pvx, double pvy, double plife, int pid) {
            if (count >= x.length) {
                int cap = int.max (64, x.length * 2);
                x.resize (cap);
                y.resize (cap);
                vx.resize (cap);
                vy.resize (cap);
                age.resize (cap);
                life.resize (cap);
                id.resize (cap);
            }
            x[count] = px;
            y[count] = py;
            vx[count] = pvx;
            vy[count] = pvy;
            age[count] = 0;
            life[count] = plife;
            id[count] = pid;
            count++;
        }
    }

    public class ParticleParams {
        public double ex;
        public double ey;
        public double radius;
        public double rate;
        public double longevity;
        public double velocity;
        public double direction;
        public double spread;
        public double inherit;
        public double evx;
        public double evy;
        public double gravity;
        public double resistance;
        public double wind_x;
        public double wind_y;
        public double turbulence;
        public double turbulence_scale;
        public bool floor;
        public double floor_y;
        public double bounce;
        public double friction;
        public int seed;
        public int max_particles = 20000;
    }

    public interface ParticleBackend : Object {
        public abstract void step (ParticleState s, ParticleParams p, double dt);
    }

    public class CpuParticleBackend : Object, ParticleBackend {
        public void step (ParticleState s, ParticleParams p, double dt) {
            s.emit_acc += p.rate * dt;
            while (s.emit_acc >= 1 && s.count < p.max_particles) {
                s.emit_acc -= 1;
                int pid = s.emitted++;
                double a = Noise.hash01 (pid, p.seed, 1) * 2 * Math.PI;
                double rr = Math.sqrt (Noise.hash01 (pid, p.seed, 2)) * p.radius;
                double dir = (p.direction - 90 + (Noise.hash01 (pid, p.seed, 3) - 0.5) * p.spread) * Math.PI / 180.0;
                double sp = p.velocity * (0.5 + Noise.hash01 (pid, p.seed, 4));
                double life = p.longevity * (0.75 + 0.5 * Noise.hash01 (pid, p.seed, 5));
                s.push (p.ex + Math.cos (a) * rr, p.ey + Math.sin (a) * rr, Math.cos (dir) * sp + p.evx * p.inherit, Math.sin (dir) * sp + p.evy * p.inherit, life, pid);
            }
            if (s.emit_acc >= 1) s.emit_acc = 0;
            int w = 0;
            for (int i = 0; i < s.count; i++) {
                double age = s.age[i] + dt;
                if (age >= s.life[i]) continue;
                double ax = p.wind_x * p.resistance, ay = p.gravity + p.wind_y * p.resistance;
                if (p.turbulence > 0) {
                    double sc = double.max (1, p.turbulence_scale);
                    ax += Noise.perlin3 (s.x[i] / sc, s.y[i] / sc, s.time * 0.5, p.seed + 11) * p.turbulence;
                    ay += Noise.perlin3 (s.x[i] / sc + 17.3, s.y[i] / sc - 4.1, s.time * 0.5, p.seed + 23) * p.turbulence;
                }
                double vx = s.vx[i] + ax * dt, vy = s.vy[i] + ay * dt;
                double damp = Math.exp (-p.resistance * dt);
                vx *= damp;
                vy *= damp;
                double nx = s.x[i] + vx * dt, ny = s.y[i] + vy * dt;
                if (p.floor && ny > p.floor_y) {
                    ny = p.floor_y - (ny - p.floor_y) * p.bounce;
                    vy = -vy * p.bounce;
                    vx *= 1 - p.friction;
                }
                s.x[w] = nx;
                s.y[w] = ny;
                s.vx[w] = vx;
                s.vy[w] = vy;
                s.age[w] = age;
                s.life[w] = s.life[i];
                s.id[w] = s.id[i];
                w++;
            }
            s.count = w;
            s.time += dt;
        }
    }

    namespace Particles {
        public const int SUBSTEPS = 4;
        public ParticleBackend backend = null;
        private Gee.HashMap<string, Gee.HashMap<int, ParticleState>>? cache = null;
        private Mutex cache_mutex;
        public int simulated_steps = 0;

        public ParticleBackend get_backend () {
            if (backend == null) backend = new CpuParticleBackend ();
            return backend;
        }

        public ParticleParams params_at (Layer layer, PropGroup fx, double lt, double fps) {
            var p = new ParticleParams ();
            var pos = fx.vec ("position", lt);
            p.ex = pos[0];
            p.ey = pos[1];
            p.radius = fx.num ("radius", lt);
            p.rate = fx.num ("birth-rate", lt) * 25;
            p.longevity = double.max (0.01, fx.num ("longevity", lt));
            p.velocity = fx.num ("velocity", lt);
            p.direction = fx.num ("direction", lt);
            p.spread = fx.num ("spread", lt);
            p.inherit = fx.num ("inherit-velocity", lt) / 100.0;
            var pp = fx.prop ("position");
            if (pp != null && pp.varies ()) {
                var v = pp.velocity_at (lt);
                p.evx = v[0];
                p.evy = v[1];
            }
            p.gravity = fx.num ("gravity", lt);
            p.resistance = fx.num ("resistance", lt);
            var wind = fx.vec ("wind", lt);
            p.wind_x = wind[0];
            p.wind_y = wind[1];
            p.turbulence = fx.num ("turbulence", lt);
            p.turbulence_scale = fx.num ("turbulence-scale", lt);
            p.floor = fx.toggle ("floor", lt);
            p.floor_y = fx.num ("floor-y", lt);
            p.bounce = fx.num ("bounce", lt) / 100.0;
            p.friction = fx.num ("friction", lt) / 100.0;
            p.seed = (int) fx.num ("seed", lt);
            p.max_particles = (int) fx.num ("max-particles", lt);
            return p;
        }

        public string cache_key (Layer layer, PropGroup fx) {
            return "%s|%s|%d".printf (layer.id, fx.key, layer.revision);
        }

        public ParticleState simulate (Layer layer, PropGroup fx, double lt, double fps) {
            cache_mutex.lock ();
            if (cache == null) cache = new Gee.HashMap<string, Gee.HashMap<int, ParticleState>> ();
            var key = cache_key (layer, fx);
            var frames = cache[key];
            if (frames == null) {
                var stale = new Gee.ArrayList<string> ();
                foreach (var k in cache.keys) if (k.has_prefix (layer.id + "|" + fx.key + "|")) stale.add (k);
                foreach (var k in stale) cache.unset (k);
                frames = new Gee.HashMap<int, ParticleState> ();
                cache[key] = frames;
            }
            cache_mutex.unlock ();
            double start_lt = layer.layer_time (layer.in_point);
            int target = (int) Math.floor ((lt - start_lt) * fps + 1e-6);
            if (target < 0) return new ParticleState ();
            int from = -1;
            ParticleState? s = null;
            cache_mutex.lock ();
            for (int f = target; f >= 0; f--) {
                if (frames.has_key (f)) {
                    from = f;
                    s = frames[f].copy ();
                    break;
                }
            }
            cache_mutex.unlock ();
            if (s == null) {
                s = new ParticleState ();
                from = 0;
                s.time = start_lt;
            }
            var be = get_backend ();
            double dt = 1.0 / (fps * SUBSTEPS);
            for (int f = from; f < target; f++) {
                for (int k = 0; k < SUBSTEPS; k++) {
                    double tt = start_lt + (f + k / (double) SUBSTEPS) / fps;
                    be.step (s, params_at (layer, fx, tt, fps), dt);
                    simulated_steps++;
                }
                cache_mutex.lock ();
                if (frames.size < 600) frames[f + 1] = s.copy ();
                cache_mutex.unlock ();
            }
            if (!frames.has_key (target)) {
                cache_mutex.lock ();
                frames[target] = s.copy ();
                cache_mutex.unlock ();
            }
            return s;
        }

        public void clear_cache () {
            cache_mutex.lock ();
            if (cache != null) cache.clear ();
            cache_mutex.unlock ();
        }

        public void register () {
            EffectRegistry.add (new EffectDef ("particle-world", _("Particle World"), _("Simulation"), (g) => {
                g.add<Property> (Factory.scalar ("birth-rate", _("Birth Rate"), 2).range (0, 1000).ui_range (0, 20));
                g.add<Property> (Factory.scalar ("longevity", _("Longevity (sec)"), 1.5).range (0.01, 100).ui_range (0.1, 10));
                g.add<Property> (Factory.point ("position", _("Producer Position"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("radius", _("Producer Radius"), 10).range (0, 10000).ui_range (0, 200));
                g.add<Property> (Factory.scalar ("velocity", _("Velocity"), 200).range (0, 100000).ui_range (0, 1000));
                g.add<Property> (Factory.angle ("direction", _("Direction"), 0));
                g.add<Property> (Factory.angle ("spread", _("Spread"), 360).range (0, 360));
                g.add<Property> (Factory.percent ("inherit-velocity", _("Inherit Velocity %"), 0).range (-1000, 1000));
                g.add<Property> (Factory.scalar ("gravity", _("Gravity"), 300).range (-100000, 100000).ui_range (-2000, 2000));
                g.add<Property> (Factory.scalar ("resistance", _("Resistance"), 0).range (0, 100).ui_range (0, 10));
                g.add<Property> (Factory.vec ("wind", _("Wind"), { 0, 0 }));
                g.add<Property> (Factory.scalar ("turbulence", _("Turbulence"), 0).range (0, 100000).ui_range (0, 2000));
                g.add<Property> (Factory.scalar ("turbulence-scale", _("Turbulence Scale"), 100).range (1, 10000).ui_range (10, 1000));
                g.add<Property> (Factory.toggle ("floor", _("Floor Collision"), false));
                g.add<Property> (Factory.scalar ("floor-y", _("Floor Position"), 1000).ui_range (0, 4000));
                g.add<Property> (Factory.percent ("bounce", _("Bounciness"), 50).range (0, 100));
                g.add<Property> (Factory.percent ("friction", _("Friction"), 10).range (0, 100));
                g.add<Property> (Factory.choice ("type", _("Particle Type"), { _("Dot"), _("Faded Sphere"), _("Square"), _("Star"), _("Textured Layer") }, 1));
                g.add<Property> (Factory.layer_ref ("texture", _("Texture Layer")));
                g.add<Property> (Factory.scalar ("birth-size", _("Birth Size"), 8).range (0, 10000).ui_range (0, 100));
                g.add<Property> (Factory.scalar ("death-size", _("Death Size"), 2).range (0, 10000).ui_range (0, 100));
                g.add<Property> (Factory.color ("birth-color", _("Birth Color"), { 1, 0.85, 0.3, 1 }));
                g.add<Property> (Factory.color ("death-color", _("Death Color"), { 0.8, 0.1, 0.05, 1 }));
                g.add<Property> (Factory.percent ("opacity", _("Max Opacity"), 100).range (0, 100));
                g.add<Property> (Factory.choice ("transfer", _("Transfer Mode"), { _("Composite"), _("Add"), _("Screen") }));
                g.add<Property> (Factory.scalar ("seed", _("Random Seed"), 1).range (0, 100000));
                g.add<Property> (Factory.scalar ("max-particles", _("Max Particles"), 20000).range (1, 200000));
            }, (ctx, fx, t) => {
                var s = simulate (ctx.layer, fx, t, ctx.comp.fps);
                render_particles (ctx, fx, t, s);
            }));
        }

        public void render_particles (EffectContext ctx, PropGroup fx, double t, ParticleState s) {
            var img = ctx.buf.img;
            var gen = new FloatImage (img.width, img.height);
            int type = fx.choice ("type", t);
            double bs = fx.num ("birth-size", t), ds = fx.num ("death-size", t);
            var bc = fx.vec ("birth-color", t);
            var dc = fx.vec ("death-color", t);
            double op = fx.num ("opacity", t) / 100.0;
            LayerBuffer? sprite = null;
            if (type == 4) {
                var tl = ctx.layer_param (fx, "texture");
                if (tl != null) sprite = ctx.renderer.layer_buffer_until (tl, ctx.comp_time, ctx.settings, ctx.depth + 1, int.MAX, 1.0);
                if (sprite == null) type = 1;
            }
            for (int i = 0; i < s.count; i++) {
                double f = s.life[i] > 0 ? (s.age[i] / s.life[i]).clamp (0, 1) : 1;
                double size = ctx.px (bs + (ds - bs) * f);
                double r = bc[0] + (dc[0] - bc[0]) * f, g = bc[1] + (dc[1] - bc[1]) * f, b = bc[2] + (dc[2] - bc[2]) * f;
                double a = op * (bc[3] + (dc[3] - bc[3]) * f);
                double px, py;
                ctx.buf.to_pixel (s.x[i], s.y[i], out px, out py);
                double rad = double.max (0.5, size / 2);
                int x0 = (int) Math.floor (px - rad - 1), x1 = (int) Math.ceil (px + rad + 1);
                int y0 = (int) Math.floor (py - rad - 1), y1 = (int) Math.ceil (py + rad + 1);
                if (x1 < 0 || y1 < 0 || x0 >= img.width || y0 >= img.height) continue;
                for (int y = int.max (0, y0); y < int.min (img.height, y1); y++)
                    for (int x = int.max (0, x0); x < int.min (img.width, x1); x++) {
                        double dx = x + 0.5 - px, dy = y + 0.5 - py;
                        double d = Math.hypot (dx, dy);
                        double cov;
                        double cr = r, cg = g, cb = b;
                        switch (type) {
                            case 0: cov = (rad + 0.5 - d).clamp (0, 1); break;
                            case 2: cov = ((rad + 0.5 - dx.abs ()).clamp (0, 1)) * ((rad + 0.5 - dy.abs ()).clamp (0, 1)); break;
                            case 3:
                                double ang = Math.atan2 (dy, dx);
                                double sr = rad * (0.45 + 0.55 * (Math.cos (ang * 5) * 0.5 + 0.5));
                                cov = (sr + 0.5 - d).clamp (0, 1);
                                break;
                            case 4:
                                double sx = (dx / rad * 0.5 + 0.5) * sprite.img.width, sy = (dy / rad * 0.5 + 0.5) * sprite.img.height;
                                if (sx < 0 || sy < 0 || sx > sprite.img.width || sy > sprite.img.height) {
                                    cov = 0;
                                    break;
                                }
                                float pr, pg, pb, pa;
                                Pixels.sample_premul (sprite.img, sx, sy, out pr, out pg, out pb, out pa);
                                cov = pa;
                                if (pa > 1e-5) {
                                    cr = pr / pa * r;
                                    cg = pg / pa * g;
                                    cb = pb / pa * b;
                                }
                                break;
                            default:
                                double u = d / rad;
                                cov = u >= 1 ? 0 : (1 - u * u) * (1 - u * u);
                                break;
                        }
                        double k = cov * a;
                        if (k <= 0) continue;
                        size_t o = gen.offset (x, y);
                        float inv = (float) (1 - k);
                        gen.data[o] = (float) (cr * k) + gen.data[o] * inv;
                        gen.data[o + 1] = (float) (cg * k) + gen.data[o + 1] * inv;
                        gen.data[o + 2] = (float) (cb * k) + gen.data[o + 2] * inv;
                        gen.data[o + 3] = (float) k + gen.data[o + 3] * inv;
                    }
            }
            int transfer = fx.choice ("transfer", t);
            var mode = transfer == 1 ? BlendMode.LINEAR_DODGE : (transfer == 2 ? BlendMode.SCREEN : BlendMode.NORMAL);
            Pixels.blend (img, new CompImage (gen, 0, 0), mode, true, false);
        }
    }
}
