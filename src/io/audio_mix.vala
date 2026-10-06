namespace Singularity.Apps.Keyframe {

    namespace AudioMix {
        public const int RATE = 48000;

        public bool comp_has_audio (Project p, Composition comp, int depth = 0) {
            if (depth > 12) return false;
            foreach (var l in comp.layers) {
                if (!l.audio) continue;
                if (l.kind == LayerKind.PRECOMP) {
                    var nested = p.comp_by_id (l.source_id);
                    if (nested != null && comp_has_audio (p, nested, depth + 1)) return true;
                    continue;
                }
                var f = p.footage_by_id (l.source_id);
                if (f != null && (f.has_audio || f.kind == FootageKind.AUDIO)) return true;
            }
            return false;
        }

        public double db_to_gain (double db) {
            if (db <= -96) return 0;
            return Math.pow (10, db / 20.0);
        }

        public AudioClip mix (Project p, MediaPool media, Composition comp, double start, double end, int depth = 0) {
            var clip = new AudioClip ();
            clip.rate = RATE;
            clip.channels = 2;
            int frames = int.max (0, (int) Math.round ((end - start) * RATE));
            clip.samples = new float[frames * 2];
            if (depth > 12 || frames == 0) return clip;
            bool solo = false;
            foreach (var l in comp.layers) if (l.solo && l.audio) solo = true;
            foreach (var l in comp.layers) {
                if (!l.audio || (solo && !l.solo)) continue;
                if (l.kind != LayerKind.FOOTAGE && l.kind != LayerKind.AUDIO && l.kind != LayerKind.PRECOMP) continue;
                double a = double.max (start, l.in_point), b = double.min (end, l.out_point);
                if (b <= a) continue;
                AudioClip? src = null;
                double src_offset = 0;
                if (l.kind == LayerKind.PRECOMP) {
                    var nested = p.comp_by_id (l.source_id);
                    if (nested == null || nested == comp || !comp_has_audio (p, nested)) continue;
                    double s0 = l.source_time (a), s1 = l.source_time (b);
                    double lo = double.max (0, double.min (s0, s1)) , hi = double.min (nested.duration, double.max (s0, s1));
                    if (l.time_remap) {
                        lo = 0;
                        hi = nested.duration;
                    }
                    if (hi <= lo) continue;
                    src = mix (p, media, nested, lo, hi, depth + 1);
                    src_offset = lo;
                } else {
                    var f = p.footage_by_id (l.source_id);
                    if (f == null || !(f.has_audio || f.kind == FootageKind.AUDIO)) continue;
                    src = media.audio_of (f);
                }
                if (src == null || src.samples.length == 0) continue;
                var levels = l.root.group ("audio") != null ? l.root.group ("audio").prop ("levels") : null;
                int f0 = (int) Math.round ((a - start) * RATE), f1 = (int) Math.round ((b - start) * RATE);
                int block = 256;
                for (int fb = f0; fb < f1; fb += block) {
                    int fe = int.min (f1, fb + block);
                    double tb = start + fb / (double) RATE;
                    double gl = 1, gr = 1;
                    if (levels != null) {
                        var v = levels.value_at (l.layer_time (tb));
                        gl = db_to_gain (v[0]);
                        gr = db_to_gain (v.length > 1 ? v[1] : v[0]);
                    }
                    for (int fi = fb; fi < fe; fi++) {
                        double t = start + fi / (double) RATE;
                        double st = l.source_time (t) - src_offset;
                        if (st < 0) continue;
                        double pos = st * src.rate;
                        int i0 = (int) Math.floor (pos);
                        float frac = (float) (pos - i0);
                        int nsrc = src.samples.length / src.channels;
                        if (i0 >= nsrc) continue;
                        int i1 = int.min (i0 + 1, nsrc - 1);
                        float l0 = src.samples[i0 * src.channels], l1 = src.samples[i1 * src.channels];
                        float r0 = src.samples[i0 * src.channels + (src.channels > 1 ? 1 : 0)], r1 = src.samples[i1 * src.channels + (src.channels > 1 ? 1 : 0)];
                        clip.samples[fi * 2] += (float) ((l0 + (l1 - l0) * frac) * gl);
                        clip.samples[fi * 2 + 1] += (float) ((r0 + (r1 - r0) * frac) * gr);
                    }
                }
            }
            return clip;
        }

        public double peak (AudioClip clip) {
            double m = 0;
            foreach (var s in clip.samples) m = double.max (m, s.abs ());
            return m;
        }

        public double rms (AudioClip clip, double from_s, double to_s) {
            int a = (int) (from_s * clip.rate) * clip.channels, b = int.min (clip.samples.length, (int) (to_s * clip.rate) * clip.channels);
            double sum = 0;
            int n = 0;
            for (int i = int.max (0, a); i < b; i++) {
                sum += clip.samples[i] * clip.samples[i];
                n++;
            }
            return n > 0 ? Math.sqrt (sum / n) : 0;
        }
    }
}
