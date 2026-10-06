using Singularity.Apps.Keyframe;

namespace Singularity.Apps.Keyframe.Cli {
    private bool stop_requested = false;

    private void on_term (int sig) {
        stop_requested = true;
    }
    private void say (string line) {
        stdout.printf ("%s\n", line);
        stdout.flush ();
    }

    private void usage () {
        stderr.printf ("%s\n", _("Usage: singularity-keyframe-render --project FILE (--item ID | --comp NAME --output PATH --format ID) [--start S] [--end S] [--resolution N] [--alpha] [--quality Q] [--bit-depth N] [--no-motion-blur] | --list-formats"));
    }

    public int run (string[] args) {
        string? project_path = null, item_id = null, comp_name = null, output = null, format = null;
        double start = -1, end = -1;
        int resolution = 1, quality = 85, bit_depth = 8;
        bool alpha = false, motion_blur = true, list = false;
        for (int i = 1; i < args.length; i++) {
            string a = args[i];
            string? next = i + 1 < args.length ? args[i + 1] : null;
            switch (a) {
                case "--project": project_path = next; i++; break;
                case "--item": item_id = next; i++; break;
                case "--comp": comp_name = next; i++; break;
                case "--output": output = next; i++; break;
                case "--format": format = next; i++; break;
                case "--start": start = double.parse (next ?? "0"); i++; break;
                case "--end": end = double.parse (next ?? "0"); i++; break;
                case "--resolution": resolution = int.parse (next ?? "1"); i++; break;
                case "--quality": quality = int.parse (next ?? "85"); i++; break;
                case "--bit-depth": bit_depth = int.parse (next ?? "8"); i++; break;
                case "--alpha": alpha = true; break;
                case "--no-motion-blur": motion_blur = false; break;
                case "--list-formats": list = true; break;
                default:
                    usage ();
                    return 1;
            }
        }
        if (list) {
            foreach (var f in Encoders.formats ()) say ("format %s|%s|%s|%s".printf (f.id, f.label, f.available ? "available" : "unavailable", f.reason));
            return 0;
        }
        if (project_path == null || (item_id == null && (comp_name == null || output == null || format == null))) {
            usage ();
            return 1;
        }
        Project project;
        try {
            project = NativeFormat.load (project_path);
        } catch (Error e) {
            say ("error " + e.message);
            return 2;
        }
        RenderItem? item = null;
        if (item_id != null) {
            foreach (var r in project.render_queue) if (r.id == item_id) item = r;
            if (item == null) {
                say ("error " + _("Render item not found"));
                return 2;
            }
        } else {
            var comp = project.comp_by_name (comp_name) ?? project.comp_by_id (comp_name);
            if (comp == null) {
                say ("error " + _("Composition not found"));
                return 2;
            }
            item = new RenderItem (comp.id);
            item.start = start;
            item.end = end;
            item.resolution = resolution;
            item.motion_blur = motion_blur;
            var om = new OutputModule ();
            om.format = format;
            om.path = output;
            om.alpha = alpha;
            om.quality = quality;
            om.bit_depth = bit_depth;
            item.outputs.add (om);
        }
        var cancel = new Cancellable ();
        Process.signal (ProcessSignal.TERM, on_term);
        Process.signal (ProcessSignal.INT, on_term);
        int last = -1;
        try {
            var outs = RenderJobs.run (project, item, cancel, (f, n) => {
                if (stop_requested) cancel.cancel ();
                if (n != last) {
                    last = n;
                    say ("frame %d".printf (n));
                }
                say ("progress %.4f".printf (f));
            });
            foreach (var o in outs) say ("done " + o);
            return 0;
        } catch (Error e) {
            say ("error " + e.message);
            return e is EncodeError && e.code == EncodeError.CANCELLED ? 4 : 3;
        }
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.setlocale (LocaleCategory.NUMERIC, "C");
    Gst.init (ref args);
    return Singularity.Apps.Keyframe.Cli.run (args);
}
