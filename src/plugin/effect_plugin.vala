namespace KeyframeEffect {

    public enum ParamKind {
        SCALAR,
        ANGLE,
        PERCENT,
        COLOR,
        POINT,
        TOGGLE
    }

    public class Param : Object {
        public string key { get; construct; }
        public string label { get; construct; }
        public ParamKind kind { get; construct; }
        public double min { get; construct; }
        public double max { get; construct; }
        public double[] default_value;

        public Param (string key, string label, ParamKind kind, double[] default_value, double min = -1000000, double max = 1000000) {
            Object (key: key, label: label, kind: kind, min: min, max: max);
            this.default_value = default_value;
        }

        public int dims () {
            return default_value.length;
        }
    }

    public interface Plugin : Object {
        public abstract string id { owned get; }
        public abstract string label { owned get; }
        public abstract string category { owned get; }
        public abstract Param[] parameters ();
        public abstract double margin (double[] values);
        public abstract void render (float[] premultiplied_rgba, int width, int height, double scale, double[] values);
    }
}
