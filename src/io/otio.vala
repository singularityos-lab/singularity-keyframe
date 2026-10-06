namespace Singularity.Apps.Keyframe {

    namespace Otio {
        private void rational (Json.Builder b, double seconds, double rate) {
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("RationalTime.1");
            b.set_member_name ("rate").add_double_value (rate);
            b.set_member_name ("value").add_double_value (Math.round (seconds * rate * 1000) / 1000);
            b.end_object ();
        }

        private void range (Json.Builder b, double start, double duration, double rate) {
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("TimeRange.1");
            b.set_member_name ("start_time");
            rational (b, start, rate);
            b.set_member_name ("duration");
            rational (b, duration, rate);
            b.end_object ();
        }

        private void reference (Json.Builder b, string url, string? comp_name, double available) {
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("ExternalReference.1");
            b.set_member_name ("target_url").add_string_value (url);
            if (available > 0) {
                b.set_member_name ("available_range");
                range (b, 0, available, 1000);
            }
            b.set_member_name ("metadata");
            b.begin_object ();
            if (comp_name != null) {
                b.set_member_name ("keyframe");
                b.begin_object ();
                b.set_member_name ("composition").add_string_value (comp_name);
                b.end_object ();
            }
            b.end_object ();
            b.end_object ();
        }

        private void clip (Json.Builder b, string name, string url, string? comp_name, double source_start, double duration, double rate, double available) {
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Clip.2");
            b.set_member_name ("name").add_string_value (name);
            b.set_member_name ("source_range");
            range (b, source_start, duration, rate);
            b.set_member_name ("media_references");
            b.begin_object ();
            b.set_member_name ("DEFAULT_MEDIA");
            reference (b, url, comp_name, available);
            b.end_object ();
            b.set_member_name ("active_media_reference_key").add_string_value ("DEFAULT_MEDIA");
            b.set_member_name ("metadata");
            b.begin_object ();
            b.end_object ();
            b.end_object ();
        }

        private void gap (Json.Builder b, double duration, double rate) {
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Gap.1");
            b.set_member_name ("name").add_string_value ("");
            b.set_member_name ("source_range");
            range (b, 0, duration, rate);
            b.end_object ();
        }

        private string file_url (string path) {
            return File.new_for_path (path).get_uri ();
        }

        public string export (Project p, Composition comp, Gee.List<string>? warnings = null) {
            double rate = comp.fps;
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Timeline.1");
            b.set_member_name ("name").add_string_value (comp.name);
            b.set_member_name ("global_start_time");
            rational (b, comp.start_timecode, rate);
            b.set_member_name ("metadata");
            b.begin_object ();
            b.set_member_name ("keyframe");
            b.begin_object ();
            b.set_member_name ("width").add_int_value (comp.width);
            b.set_member_name ("height").add_int_value (comp.height);
            b.end_object ();
            b.end_object ();
            b.set_member_name ("tracks");
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Stack.1");
            b.set_member_name ("name").add_string_value ("tracks");
            b.set_member_name ("children");
            b.begin_array ();
            for (int i = comp.layers.size - 1; i >= 0; i--) {
                var l = comp.layers[i];
                string? url = null;
                string? comp_name = null;
                double available = 0;
                string kind = "Video";
                if (l.kind == LayerKind.FOOTAGE || l.kind == LayerKind.AUDIO) {
                    var f = p.footage_by_id (l.source_id);
                    if (f == null) continue;
                    url = file_url (f.kind == FootageKind.SEQUENCE ? f.sequence_frame_path (0) : f.path);
                    available = f.duration;
                    if (l.kind == LayerKind.AUDIO) kind = "Audio";
                } else if (l.kind == LayerKind.PRECOMP) {
                    var nested = p.comp_by_id (l.source_id);
                    if (nested == null) continue;
                    if (p.path == "") {
                        if (warnings != null) warnings.add (_("Save the project first so “%s” can be referenced").printf (l.name));
                        continue;
                    }
                    url = file_url (p.path);
                    comp_name = nested.name;
                    available = nested.duration;
                } else {
                    if (warnings != null) warnings.add (_("Layer “%s” has no media and is not part of the OpenTimelineIO export").printf (l.name));
                    continue;
                }
                if (l.stretch != 1 || l.time_remap) {
                    if (warnings != null) warnings.add (_("Time stretch and remapping of “%s” are not exported").printf (l.name));
                }
                b.begin_object ();
                b.set_member_name ("OTIO_SCHEMA").add_string_value ("Track.1");
                b.set_member_name ("name").add_string_value (l.name);
                b.set_member_name ("kind").add_string_value (kind);
                b.set_member_name ("enabled").add_boolean_value (l.video || l.audio);
                b.set_member_name ("children");
                b.begin_array ();
                if (l.in_point > 1e-6) gap (b, l.in_point, rate);
                clip (b, l.name, url, comp_name, l.in_point - l.start_time, l.out_point - l.in_point, rate, available);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            b.end_object ();
            return JsonUtil.to_string (b.get_root (), true);
        }

        public string composition_reference (Project p, Composition comp) {
            double rate = comp.fps;
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Timeline.1");
            b.set_member_name ("name").add_string_value (comp.name);
            b.set_member_name ("tracks");
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Stack.1");
            b.set_member_name ("children");
            b.begin_array ();
            b.begin_object ();
            b.set_member_name ("OTIO_SCHEMA").add_string_value ("Track.1");
            b.set_member_name ("name").add_string_value (comp.name);
            b.set_member_name ("kind").add_string_value ("Video");
            b.set_member_name ("children");
            b.begin_array ();
            clip (b, comp.name, file_url (p.path), comp.name, 0, comp.duration, rate, comp.duration);
            b.end_array ();
            b.end_object ();
            b.end_array ();
            b.end_object ();
            b.end_object ();
            return JsonUtil.to_string (b.get_root (), true);
        }

        private double seconds (Json.Object? rt) {
            if (rt == null) return 0;
            double rate = JsonUtil.num (rt, "rate", 1);
            return rate > 0 ? JsonUtil.num (rt, "value", 0) / rate : 0;
        }

        private void range_of (Json.Object o, out double start, out double duration) {
            start = 0;
            duration = 0;
            if (!o.has_member ("source_range") || o.get_member ("source_range").get_node_type () != Json.NodeType.OBJECT) return;
            var r = o.get_object_member ("source_range");
            start = seconds (r.has_member ("start_time") ? r.get_object_member ("start_time") : null);
            duration = seconds (r.has_member ("duration") ? r.get_object_member ("duration") : null);
        }

        private Json.Object? media_ref (Json.Object clip) {
            if (clip.has_member ("media_references")) {
                var refs = clip.get_object_member ("media_references");
                var key = JsonUtil.str (clip, "active_media_reference_key", "DEFAULT_MEDIA");
                if (refs.has_member (key)) return refs.get_object_member (key);
                foreach (var m in refs.get_members ()) return refs.get_object_member (m);
            }
            if (clip.has_member ("media_reference") && clip.get_member ("media_reference").get_node_type () == Json.NodeType.OBJECT) return clip.get_object_member ("media_reference");
            return null;
        }

        public Composition import_text (Project p, string text, Gee.List<string>? warnings = null) throws Error {
            var root = JsonUtil.parse (text).get_object ();
            if (!JsonUtil.str (root, "OTIO_SCHEMA").has_prefix ("Timeline")) throw new ProjectError.FORMAT (_("This is not an OpenTimelineIO timeline"));
            var comp = new Composition (JsonUtil.str (root, "name", _("Timeline")));
            double rate = 0;
            double total = 0;
            if (root.has_member ("metadata")) {
                var md = root.get_object_member ("metadata");
                if (md.has_member ("keyframe")) {
                    var k = md.get_object_member ("keyframe");
                    comp.width = (int) JsonUtil.num (k, "width", comp.width);
                    comp.height = (int) JsonUtil.num (k, "height", comp.height);
                }
            }
            p.add_item (comp);
            var tracks = root.get_object_member ("tracks");
            var footage_cache = new Gee.HashMap<string, Item> ();
            foreach (var te in tracks.get_array_member ("children").get_elements ()) {
                var track = te.get_object ();
                if (!JsonUtil.str (track, "OTIO_SCHEMA").has_prefix ("Track")) continue;
                double cursor = 0;
                foreach (var ce in track.get_array_member ("children").get_elements ()) {
                    var item = ce.get_object ();
                    string schema = JsonUtil.str (item, "OTIO_SCHEMA");
                    double start, duration;
                    range_of (item, out start, out duration);
                    if (schema.has_prefix ("Gap")) {
                        cursor += duration;
                        continue;
                    }
                    if (!schema.has_prefix ("Clip")) {
                        if (warnings != null) warnings.add (_("OpenTimelineIO item “%s” is not supported").printf (schema));
                        cursor += duration;
                        continue;
                    }
                    if (rate == 0 && item.has_member ("source_range")) {
                        var sr = item.get_object_member ("source_range");
                        if (sr.has_member ("duration")) rate = JsonUtil.num (sr.get_object_member ("duration"), "rate", 0);
                    }
                    var mr = media_ref (item);
                    string url = mr != null ? JsonUtil.str (mr, "target_url") : "";
                    string? comp_ref = null;
                    if (mr != null && mr.has_member ("metadata")) {
                        var md = mr.get_object_member ("metadata");
                        if (md.has_member ("keyframe")) comp_ref = JsonUtil.str (md.get_object_member ("keyframe"), "composition");
                    }
                    Layer? layer = null;
                    if (comp_ref != null && comp_ref != "") {
                        var nested = p.comp_by_name (comp_ref);
                        if (nested != null && nested != comp) layer = Factory.precomp_layer (comp, nested);
                        else if (warnings != null) warnings.add (_("Composition “%s” is not in this project").printf (comp_ref));
                    }
                    if (layer == null && url != "") {
                        string path = url.has_prefix ("file://") ? File.new_for_uri (url).get_path () : url;
                        Footage f;
                        if (footage_cache.has_key (path)) f = (Footage) footage_cache[path];
                        else {
                            try {
                                f = MediaPool.probe (path);
                            } catch (Error e) {
                                f = new Footage (path, JsonUtil.str (track, "kind") == "Audio" ? FootageKind.AUDIO : FootageKind.VIDEO);
                                if (warnings != null) warnings.add (_("Media “%s” could not be read").printf (Path.get_basename (path)));
                            }
                            p.add_item (f);
                            footage_cache[path] = f;
                        }
                        layer = Factory.footage_layer (comp, f);
                    }
                    if (layer != null) {
                        layer.name = comp.unique_layer_name (JsonUtil.str (item, "name", layer.name));
                        layer.in_point = cursor;
                        layer.out_point = cursor + duration;
                        layer.start_time = cursor - start;
                        layer.video = JsonUtil.bool_of (track, "enabled", true);
                        comp.layers.insert (0, layer);
                        layer.comp = comp;
                    }
                    cursor += duration;
                }
                total = double.max (total, cursor);
            }
            if (rate > 0) comp.fps = rate;
            comp.duration = double.max (1.0 / comp.fps, total);
            return comp;
        }
    }
}
