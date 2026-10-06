namespace Singularity.Apps.Keyframe {

    public errordomain ProjectError {
        FORMAT,
        VERSION
    }

    namespace NativeFormat {
        public const string MIME = "application/x-keyframe";
        public const int VERSION = 1;

        public void write_node (Json.Builder b, PropNode node) {
            b.begin_object ();
            var p = node as Property;
            if (p != null) {
                b.set_member_name ("prop").add_string_value (p.key);
                b.set_member_name ("name").add_string_value (p.name);
                b.set_member_name ("kind").add_string_value (p.kind.to_id ());
                if (p.kind == PropKind.PATH) {
                    b.set_member_name ("path").add_string_value ((p.path ?? new BezPath ()).serialize ());
                } else if (p.kind == PropKind.TEXT) {
                    b.set_member_name ("text").add_value ((p.text ?? new TextDocument ()).to_json ());
                } else {
                    b.set_member_name ("value");
                    JsonUtil.add_array (b, p.value);
                }
                if (p.min > -double.MAX) b.set_member_name ("min").add_double_value (p.min);
                if (p.max < double.MAX) b.set_member_name ("max").add_double_value (p.max);
                b.set_member_name ("uiMin").add_double_value (p.ui_min);
                b.set_member_name ("uiMax").add_double_value (p.ui_max);
                if (p.choices.length > 0) {
                    b.set_member_name ("choices");
                    b.begin_array ();
                    foreach (var c in p.choices) b.add_string_value (c);
                    b.end_array ();
                }
                if (!p.animatable) b.set_member_name ("static").add_boolean_value (true);
                if (p.spatial) b.set_member_name ("spatial").add_boolean_value (true);
                if (p.unit != "") b.set_member_name ("unit").add_string_value (p.unit);
                if (p.expression != "") {
                    b.set_member_name ("expression").add_string_value (p.expression);
                    b.set_member_name ("expressionOn").add_boolean_value (p.expression_enabled);
                }
                if (p.keys.size > 0) {
                    b.set_member_name ("keys");
                    b.begin_array ();
                    foreach (var k in p.keys) write_key (b, p, k);
                    b.end_array ();
                }
            } else {
                var g = (PropGroup) node;
                b.set_member_name ("group").add_string_value (g.type);
                b.set_member_name ("key").add_string_value (g.key);
                b.set_member_name ("name").add_string_value (g.name);
                if (!g.enabled) b.set_member_name ("enabled").add_boolean_value (false);
                if (g.attrs.size > 0) {
                    b.set_member_name ("attrs");
                    b.begin_object ();
                    var keys = new Gee.ArrayList<string> ();
                    keys.add_all (g.attrs.keys);
                    keys.sort ();
                    foreach (var k in keys) b.set_member_name (k).add_string_value (g.attrs[k]);
                    b.end_object ();
                }
                b.set_member_name ("children");
                b.begin_array ();
                foreach (var c in g.children) write_node (b, c);
                b.end_array ();
            }
            b.end_object ();
        }

        private void write_key (Json.Builder b, Property p, Keyframe k) {
            b.begin_object ();
            b.set_member_name ("t").add_double_value (k.time);
            if (p.kind == PropKind.PATH) b.set_member_name ("path").add_string_value ((k.path ?? new BezPath ()).serialize ());
            else if (p.kind == PropKind.TEXT) b.set_member_name ("text").add_value ((k.text ?? new TextDocument ()).to_json ());
            else {
                b.set_member_name ("v");
                JsonUtil.add_array (b, k.value);
            }
            b.set_member_name ("in").add_string_value (k.in_interp.to_id ());
            b.set_member_name ("out").add_string_value (k.out_interp.to_id ());
            if (k.in_interp == Interp.BEZIER) {
                b.set_member_name ("easeIn");
                JsonUtil.add_array (b, { k.ease_in_x, k.ease_in_y });
            }
            if (k.out_interp == Interp.BEZIER) {
                b.set_member_name ("easeOut");
                JsonUtil.add_array (b, { k.ease_out_x, k.ease_out_y });
            }
            if (k.auto_bezier) b.set_member_name ("auto").add_boolean_value (true);
            if (k.continuous) b.set_member_name ("continuous").add_boolean_value (true);
            if (k.roving) b.set_member_name ("roving").add_boolean_value (true);
            if (p.spatial) {
                b.set_member_name ("spatialAuto").add_boolean_value (k.spatial_auto);
                if (!k.spatial_auto) {
                    b.set_member_name ("tin");
                    JsonUtil.add_array (b, k.tangent_in);
                    b.set_member_name ("tout");
                    JsonUtil.add_array (b, k.tangent_out);
                }
            }
            b.end_object ();
        }

        public PropNode read_node (Json.Object o) {
            if (o.has_member ("prop")) {
                var kind = PropKind.from_id (JsonUtil.str (o, "kind"));
                Property p;
                if (kind == PropKind.PATH) p = new Property.with_path (JsonUtil.str (o, "prop"), JsonUtil.str (o, "name"), BezPath.parse (JsonUtil.str (o, "path", "c")));
                else if (kind == PropKind.TEXT) p = new Property.with_text (JsonUtil.str (o, "prop"), JsonUtil.str (o, "name"), o.has_member ("text") ? TextDocument.from_json (o.get_object_member ("text")) : new TextDocument ());
                else p = new Property (JsonUtil.str (o, "prop"), JsonUtil.str (o, "name"), kind, JsonUtil.array (o, "value", { 0 }));
                p.min = JsonUtil.num (o, "min", -double.MAX);
                p.max = JsonUtil.num (o, "max", double.MAX);
                p.ui_min = JsonUtil.num (o, "uiMin", -1000);
                p.ui_max = JsonUtil.num (o, "uiMax", 1000);
                if (o.has_member ("choices")) {
                    string[] c = {};
                    foreach (var e in o.get_array_member ("choices").get_elements ()) c += e.get_string ();
                    p.choices = c;
                }
                p.animatable = !JsonUtil.bool_of (o, "static", false);
                p.spatial = JsonUtil.bool_of (o, "spatial", false);
                p.unit = JsonUtil.str (o, "unit", "");
                p.expression = JsonUtil.str (o, "expression", "");
                p.expression_enabled = JsonUtil.bool_of (o, "expressionOn", true);
                if (o.has_member ("keys")) {
                    foreach (var e in o.get_array_member ("keys").get_elements ()) p.keys.add (read_key (p, e.get_object ()));
                    p.sort_keys ();
                }
                return p;
            }
            var g = new PropGroup (JsonUtil.str (o, "group", "group"), JsonUtil.str (o, "key"), JsonUtil.str (o, "name"));
            g.enabled = JsonUtil.bool_of (o, "enabled", true);
            if (o.has_member ("attrs")) {
                var a = o.get_object_member ("attrs");
                foreach (var m in a.get_members ()) g.attrs[m] = a.get_string_member (m);
            }
            if (o.has_member ("children"))
                foreach (var e in o.get_array_member ("children").get_elements ()) g.add<PropNode> (read_node (e.get_object ()));
            return g;
        }

        private Keyframe read_key (Property p, Json.Object o) {
            var k = new Keyframe (JsonUtil.num (o, "t"));
            if (p.kind == PropKind.PATH) k.path = BezPath.parse (JsonUtil.str (o, "path", "c"));
            else if (p.kind == PropKind.TEXT) k.text = o.has_member ("text") ? TextDocument.from_json (o.get_object_member ("text")) : new TextDocument ();
            else k.value = JsonUtil.array (o, "v", p.value);
            k.in_interp = Interp.from_id (JsonUtil.str (o, "in"));
            k.out_interp = Interp.from_id (JsonUtil.str (o, "out"));
            var ei = JsonUtil.array (o, "easeIn", { 2.0 / 3.0, 1 });
            var eo = JsonUtil.array (o, "easeOut", { 1.0 / 3.0, 0 });
            k.ease_in_x = ei[0];
            k.ease_in_y = ei[1];
            k.ease_out_x = eo[0];
            k.ease_out_y = eo[1];
            k.auto_bezier = JsonUtil.bool_of (o, "auto", false);
            k.continuous = JsonUtil.bool_of (o, "continuous", false);
            k.roving = JsonUtil.bool_of (o, "roving", false);
            k.spatial_auto = JsonUtil.bool_of (o, "spatialAuto", true);
            k.tangent_in = JsonUtil.array (o, "tin", {});
            k.tangent_out = JsonUtil.array (o, "tout", {});
            return k;
        }

        public void write_layer (Json.Builder b, Layer l) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (l.id);
            b.set_member_name ("name").add_string_value (l.name);
            b.set_member_name ("kind").add_string_value (l.kind.to_id ());
            if (l.source_id != "") b.set_member_name ("source").add_string_value (l.source_id);
            b.set_member_name ("label").add_int_value (l.label);
            b.set_member_name ("video").add_boolean_value (l.video);
            b.set_member_name ("audio").add_boolean_value (l.audio);
            b.set_member_name ("solo").add_boolean_value (l.solo);
            b.set_member_name ("locked").add_boolean_value (l.locked);
            b.set_member_name ("shy").add_boolean_value (l.shy);
            b.set_member_name ("motionBlur").add_boolean_value (l.motion_blur);
            b.set_member_name ("threeD").add_boolean_value (l.three_d);
            b.set_member_name ("adjustment").add_boolean_value (l.adjustment);
            b.set_member_name ("collapse").add_boolean_value (l.collapse);
            b.set_member_name ("guide").add_boolean_value (l.guide);
            b.set_member_name ("frameBlend").add_boolean_value (l.frame_blend);
            b.set_member_name ("parent").add_string_value (l.parent_id);
            b.set_member_name ("in").add_double_value (l.in_point);
            b.set_member_name ("out").add_double_value (l.out_point);
            b.set_member_name ("start").add_double_value (l.start_time);
            b.set_member_name ("stretch").add_double_value (l.stretch);
            b.set_member_name ("blend").add_string_value (l.blend.key ());
            b.set_member_name ("matte").add_string_value (l.matte_id);
            b.set_member_name ("matteMode").add_string_value (l.matte_mode.to_id ());
            b.set_member_name ("preserveTransparency").add_boolean_value (l.preserve_transparency);
            b.set_member_name ("autoOrient").add_string_value (l.auto_orient.to_id ());
            b.set_member_name ("solidColor");
            JsonUtil.add_array (b, l.solid_color);
            b.set_member_name ("width").add_int_value (l.solid_width);
            b.set_member_name ("height").add_int_value (l.solid_height);
            b.set_member_name ("timeRemap").add_boolean_value (l.time_remap);
            if (l.comment != "") b.set_member_name ("comment").add_string_value (l.comment);
            b.set_member_name ("props");
            write_node (b, l.root);
            b.end_object ();
        }

        public Layer read_layer (Json.Object o) {
            var l = new Layer (LayerKind.from_id (JsonUtil.str (o, "kind")), JsonUtil.str (o, "name"));
            l.id = JsonUtil.str (o, "id", l.id);
            l.source_id = JsonUtil.str (o, "source");
            l.label = (int) JsonUtil.num (o, "label");
            l.video = JsonUtil.bool_of (o, "video", true);
            l.audio = JsonUtil.bool_of (o, "audio", true);
            l.solo = JsonUtil.bool_of (o, "solo");
            l.locked = JsonUtil.bool_of (o, "locked");
            l.shy = JsonUtil.bool_of (o, "shy");
            l.motion_blur = JsonUtil.bool_of (o, "motionBlur");
            l.three_d = JsonUtil.bool_of (o, "threeD");
            l.adjustment = JsonUtil.bool_of (o, "adjustment");
            l.collapse = JsonUtil.bool_of (o, "collapse");
            l.guide = JsonUtil.bool_of (o, "guide");
            l.frame_blend = JsonUtil.bool_of (o, "frameBlend");
            l.parent_id = JsonUtil.str (o, "parent");
            l.in_point = JsonUtil.num (o, "in");
            l.out_point = JsonUtil.num (o, "out", 10);
            l.start_time = JsonUtil.num (o, "start");
            l.stretch = JsonUtil.num (o, "stretch", 1);
            l.blend = Singularity.Imaging.BlendMode.from_key (JsonUtil.str (o, "blend", "normal"));
            l.matte_id = JsonUtil.str (o, "matte");
            l.matte_mode = MatteMode.from_id (JsonUtil.str (o, "matteMode"));
            l.preserve_transparency = JsonUtil.bool_of (o, "preserveTransparency");
            l.auto_orient = AutoOrient.from_id (JsonUtil.str (o, "autoOrient"));
            l.solid_color = JsonUtil.array (o, "solidColor", l.solid_color);
            l.solid_width = (int) JsonUtil.num (o, "width", 1920);
            l.solid_height = (int) JsonUtil.num (o, "height", 1080);
            l.time_remap = JsonUtil.bool_of (o, "timeRemap");
            l.comment = JsonUtil.str (o, "comment");
            if (o.has_member ("props")) {
                var root = read_node (o.get_object_member ("props")) as PropGroup;
                if (root != null) {
                    l.root = root;
                    root.layer = l;
                }
            }
            return l;
        }

        public void write_comp (Json.Builder b, Composition c) {
            b.set_member_name ("width").add_int_value (c.width);
            b.set_member_name ("height").add_int_value (c.height);
            b.set_member_name ("pixelAspect").add_double_value (c.pixel_aspect);
            b.set_member_name ("fps").add_double_value (c.fps);
            b.set_member_name ("duration").add_double_value (c.duration);
            b.set_member_name ("startTimecode").add_double_value (c.start_timecode);
            b.set_member_name ("background");
            JsonUtil.add_array (b, c.background);
            b.set_member_name ("workStart").add_double_value (c.work_start);
            b.set_member_name ("workEnd").add_double_value (c.work_end);
            b.set_member_name ("shutterAngle").add_double_value (c.shutter_angle);
            b.set_member_name ("shutterPhase").add_double_value (c.shutter_phase);
            b.set_member_name ("motionBlurSamples").add_int_value (c.motion_blur_samples);
            b.set_member_name ("motionBlurEnabled").add_boolean_value (c.motion_blur_enabled);
            b.set_member_name ("hideShy").add_boolean_value (c.hide_shy);
            b.set_member_name ("frameBlending").add_boolean_value (c.frame_blending);
            b.set_member_name ("markers");
            b.begin_array ();
            foreach (var m in c.markers) {
                b.begin_object ();
                b.set_member_name ("t").add_double_value (m.time);
                b.set_member_name ("d").add_double_value (m.duration);
                b.set_member_name ("comment").add_string_value (m.comment);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("essential");
            b.begin_array ();
            foreach (var e in c.essential) {
                b.begin_object ();
                b.set_member_name ("layer").add_string_value (e.layer_id);
                b.set_member_name ("path").add_string_value (e.path);
                b.set_member_name ("label").add_string_value (e.label);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("layers");
            b.begin_array ();
            foreach (var l in c.layers) write_layer (b, l);
            b.end_array ();
        }

        public void read_comp (Composition c, Json.Object o) {
            c.width = (int) JsonUtil.num (o, "width", 1920);
            c.height = (int) JsonUtil.num (o, "height", 1080);
            c.pixel_aspect = JsonUtil.num (o, "pixelAspect", 1);
            c.fps = JsonUtil.num (o, "fps", 30);
            c.duration = JsonUtil.num (o, "duration", 10);
            c.start_timecode = JsonUtil.num (o, "startTimecode", 0);
            c.background = JsonUtil.array (o, "background", c.background);
            c.work_start = JsonUtil.num (o, "workStart", 0);
            c.work_end = JsonUtil.num (o, "workEnd", -1);
            c.shutter_angle = JsonUtil.num (o, "shutterAngle", 180);
            c.shutter_phase = JsonUtil.num (o, "shutterPhase", -90);
            c.motion_blur_samples = (int) JsonUtil.num (o, "motionBlurSamples", 16);
            c.motion_blur_enabled = JsonUtil.bool_of (o, "motionBlurEnabled", true);
            c.hide_shy = JsonUtil.bool_of (o, "hideShy", false);
            c.frame_blending = JsonUtil.bool_of (o, "frameBlending", false);
            if (o.has_member ("markers"))
                foreach (var e in o.get_array_member ("markers").get_elements ()) {
                    var mo = e.get_object ();
                    c.markers.add (new Marker (JsonUtil.num (mo, "t"), JsonUtil.str (mo, "comment"), JsonUtil.num (mo, "d")));
                }
            if (o.has_member ("essential"))
                foreach (var e in o.get_array_member ("essential").get_elements ()) {
                    var eo = e.get_object ();
                    c.essential.add (new EssentialProperty (JsonUtil.str (eo, "layer"), JsonUtil.str (eo, "path"), JsonUtil.str (eo, "label")));
                }
            if (o.has_member ("layers"))
                foreach (var e in o.get_array_member ("layers").get_elements ()) {
                    var l = read_layer (e.get_object ());
                    l.comp = c;
                    c.layers.add (l);
                }
        }

        public Json.Node project_to_json (Project p) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("format").add_string_value ("keyframe");
            b.set_member_name ("version").add_int_value (VERSION);
            b.set_member_name ("bitDepth").add_int_value (p.bit_depth);
            b.set_member_name ("workingSpace").add_string_value (p.working_space);
            b.set_member_name ("displaySpace").add_string_value (p.display_space);
            b.set_member_name ("ocioConfig").add_string_value (p.ocio_config);
            b.set_member_name ("linearBlending").add_boolean_value (p.linear_blending);
            b.set_member_name ("items");
            b.begin_array ();
            foreach (var item in p.items) {
                b.begin_object ();
                b.set_member_name ("type").add_string_value (item.kind_id ());
                b.set_member_name ("id").add_string_value (item.id);
                b.set_member_name ("name").add_string_value (item.name);
                b.set_member_name ("folder").add_string_value (item.folder_id);
                b.set_member_name ("label").add_int_value (item.label);
                if (item.comment != "") b.set_member_name ("comment").add_string_value (item.comment);
                var f = item as Footage;
                if (f != null) write_footage (b, p, f);
                var c = item as Composition;
                if (c != null) write_comp (b, c);
                var d = item as Folder;
                if (d != null) b.set_member_name ("expanded").add_boolean_value (d.expanded);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("compositions");
            b.begin_array ();
            foreach (var c in p.compositions ()) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (c.id);
                b.set_member_name ("name").add_string_value (c.name);
                b.set_member_name ("width").add_int_value (c.width);
                b.set_member_name ("height").add_int_value (c.height);
                b.set_member_name ("fps").add_double_value (c.fps);
                b.set_member_name ("duration").add_double_value (c.duration);
                b.set_member_name ("essential");
                b.begin_array ();
                foreach (var e in c.essential) {
                    b.begin_object ();
                    b.set_member_name ("layer").add_string_value (e.layer_id);
                    b.set_member_name ("path").add_string_value (e.path);
                    b.set_member_name ("label").add_string_value (e.label);
                    b.end_object ();
                }
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("renderQueue");
            b.begin_array ();
            foreach (var r in p.render_queue) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (r.id);
                b.set_member_name ("comp").add_string_value (r.comp_id);
                b.set_member_name ("status").add_string_value (r.status.to_id ());
                b.set_member_name ("start").add_double_value (r.start);
                b.set_member_name ("end").add_double_value (r.end);
                b.set_member_name ("resolution").add_int_value (r.resolution);
                b.set_member_name ("motionBlur").add_boolean_value (r.motion_blur);
                b.set_member_name ("outputs");
                b.begin_array ();
                foreach (var om in r.outputs) write_output (b, om);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return b.get_root ();
        }

        public void write_output (Json.Builder b, OutputModule om) {
            b.begin_object ();
            b.set_member_name ("format").add_string_value (om.format);
            b.set_member_name ("path").add_string_value (om.path);
            b.set_member_name ("alpha").add_boolean_value (om.alpha);
            b.set_member_name ("bitDepth").add_int_value (om.bit_depth);
            b.set_member_name ("quality").add_int_value (om.quality);
            b.set_member_name ("bitrate").add_int_value (om.bitrate_kbps);
            b.set_member_name ("audio").add_boolean_value (om.include_audio);
            b.set_member_name ("audioFormat").add_string_value (om.audio_format);
            b.set_member_name ("width").add_int_value (om.width);
            b.set_member_name ("height").add_int_value (om.height);
            b.set_member_name ("colorSpace").add_string_value (om.color_space);
            b.end_object ();
        }

        public OutputModule read_output (Json.Object o) {
            var om = new OutputModule ();
            om.format = JsonUtil.str (o, "format", om.format);
            om.path = JsonUtil.str (o, "path");
            om.alpha = JsonUtil.bool_of (o, "alpha");
            om.bit_depth = (int) JsonUtil.num (o, "bitDepth", 8);
            om.quality = (int) JsonUtil.num (o, "quality", 85);
            om.bitrate_kbps = (int) JsonUtil.num (o, "bitrate", 0);
            om.include_audio = JsonUtil.bool_of (o, "audio", true);
            om.audio_format = JsonUtil.str (o, "audioFormat");
            om.width = (int) JsonUtil.num (o, "width");
            om.height = (int) JsonUtil.num (o, "height");
            om.color_space = JsonUtil.str (o, "colorSpace");
            return om;
        }

        private void write_footage (Json.Builder b, Project p, Footage f) {
            b.set_member_name ("path").add_string_value (relative_path (p, f.path));
            b.set_member_name ("kind").add_string_value (f.kind.to_id ());
            b.set_member_name ("width").add_int_value (f.width);
            b.set_member_name ("height").add_int_value (f.height);
            b.set_member_name ("fps").add_double_value (f.fps);
            b.set_member_name ("duration").add_double_value (f.duration);
            b.set_member_name ("hasVideo").add_boolean_value (f.has_video);
            b.set_member_name ("hasAudio").add_boolean_value (f.has_audio);
            b.set_member_name ("hasAlpha").add_boolean_value (f.has_alpha);
            b.set_member_name ("premultiplied").add_boolean_value (f.premultiplied);
            b.set_member_name ("colorSpace").add_string_value (f.color_space);
            b.set_member_name ("proxy").add_string_value (relative_path (p, f.proxy_path));
            b.set_member_name ("useProxy").add_boolean_value (f.use_proxy);
            b.set_member_name ("seqFirst").add_int_value (f.seq_first);
            b.set_member_name ("seqLast").add_int_value (f.seq_last);
            b.set_member_name ("seqDigits").add_int_value (f.seq_digits);
            b.set_member_name ("seqPrefix").add_string_value (relative_path (p, f.seq_prefix));
            b.set_member_name ("seqSuffix").add_string_value (f.seq_suffix);
            b.set_member_name ("loop").add_int_value (f.loop);
            b.set_member_name ("fpsOverride").add_double_value (f.fps_override);
        }

        private string relative_path (Project p, string path) {
            if (path == "" || p.base_dir == "" || !Path.is_absolute (path)) return path;
            var base_file = File.new_for_path (p.base_dir);
            var rel = base_file.get_relative_path (File.new_for_path (path));
            return rel ?? path;
        }

        private Footage read_footage (Project p, Json.Object o) {
            var f = new Footage (p.resolve_path (JsonUtil.str (o, "path")), FootageKind.from_id (JsonUtil.str (o, "kind")));
            f.width = (int) JsonUtil.num (o, "width");
            f.height = (int) JsonUtil.num (o, "height");
            f.fps = JsonUtil.num (o, "fps");
            f.duration = JsonUtil.num (o, "duration");
            f.has_video = JsonUtil.bool_of (o, "hasVideo", true);
            f.has_audio = JsonUtil.bool_of (o, "hasAudio");
            f.has_alpha = JsonUtil.bool_of (o, "hasAlpha");
            f.premultiplied = JsonUtil.bool_of (o, "premultiplied");
            f.color_space = JsonUtil.str (o, "colorSpace", "srgb");
            f.proxy_path = p.resolve_path (JsonUtil.str (o, "proxy"));
            f.use_proxy = JsonUtil.bool_of (o, "useProxy");
            f.seq_first = (int) JsonUtil.num (o, "seqFirst");
            f.seq_last = (int) JsonUtil.num (o, "seqLast");
            f.seq_digits = (int) JsonUtil.num (o, "seqDigits", 4);
            f.seq_prefix = p.resolve_path (JsonUtil.str (o, "seqPrefix"));
            f.seq_suffix = JsonUtil.str (o, "seqSuffix");
            f.loop = (int) JsonUtil.num (o, "loop", 1);
            f.fps_override = JsonUtil.num (o, "fpsOverride");
            return f;
        }

        public Project project_from_json (Json.Node root, string base_dir = "") throws ProjectError {
            if (root.get_node_type () != Json.NodeType.OBJECT) throw new ProjectError.FORMAT ("Not a Keyframe project");
            var o = root.get_object ();
            if (JsonUtil.str (o, "format") != "keyframe") throw new ProjectError.FORMAT ("Not a Keyframe project");
            if ((int) JsonUtil.num (o, "version", 1) > VERSION) throw new ProjectError.VERSION ("This project was saved by a newer version of Keyframe");
            var p = new Project ();
            p.base_dir = base_dir;
            p.bit_depth = (int) JsonUtil.num (o, "bitDepth", 32);
            p.working_space = JsonUtil.str (o, "workingSpace", "linear-srgb");
            p.display_space = JsonUtil.str (o, "displaySpace", "srgb");
            p.ocio_config = JsonUtil.str (o, "ocioConfig", "");
            p.linear_blending = JsonUtil.bool_of (o, "linearBlending", true);
            if (o.has_member ("items"))
                foreach (var e in o.get_array_member ("items").get_elements ()) {
                    var io = e.get_object ();
                    Item item;
                    switch (JsonUtil.str (io, "type")) {
                        case "folder":
                            var d = new Folder (JsonUtil.str (io, "name"));
                            d.expanded = JsonUtil.bool_of (io, "expanded", true);
                            item = d;
                            break;
                        case "footage":
                            item = read_footage (p, io);
                            break;
                        default:
                            var c = new Composition (JsonUtil.str (io, "name"));
                            c.project = p;
                            read_comp (c, io);
                            item = c;
                            break;
                    }
                    item.id = JsonUtil.str (io, "id", item.id);
                    item.name = JsonUtil.str (io, "name", item.name);
                    item.folder_id = JsonUtil.str (io, "folder");
                    item.label = (int) JsonUtil.num (io, "label");
                    item.comment = JsonUtil.str (io, "comment");
                    p.items.add (item);
                }
            if (o.has_member ("renderQueue"))
                foreach (var e in o.get_array_member ("renderQueue").get_elements ()) {
                    var ro = e.get_object ();
                    var r = new RenderItem (JsonUtil.str (ro, "comp"));
                    r.id = JsonUtil.str (ro, "id", r.id);
                    r.status = RenderStatus.from_id (JsonUtil.str (ro, "status"));
                    if (r.status == RenderStatus.RENDERING) r.status = RenderStatus.QUEUED;
                    r.start = JsonUtil.num (ro, "start");
                    r.end = JsonUtil.num (ro, "end", -1);
                    r.resolution = (int) JsonUtil.num (ro, "resolution", 1);
                    r.motion_blur = JsonUtil.bool_of (ro, "motionBlur", true);
                    if (ro.has_member ("outputs"))
                        foreach (var oe in ro.get_array_member ("outputs").get_elements ()) r.outputs.add (read_output (oe.get_object ()));
                    p.render_queue.add (r);
                }
            p.modified = false;
            return p;
        }

        public uint8[] save_bytes (Project p) throws Error {
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", MIME, false);
            zip.add_text ("project.json", JsonUtil.to_string (project_to_json (p)));
            return zip.finish ();
        }

        public void save (Project p, string path) throws Error {
            string old_base = p.base_dir;
            p.base_dir = Path.get_dirname (path);
            try {
                FileUtils.set_data (path, save_bytes (p));
            } catch (Error e) {
                p.base_dir = old_base;
                throw e;
            }
            p.path = path;
            p.modified = false;
        }

        public Project load_bytes (uint8[] data, string base_dir = "") throws Error {
            var zip = new ZipReader (data);
            var text = zip.read_text ("project.json");
            if (text == null) throw new ProjectError.FORMAT ("The file has no project.json");
            return project_from_json (JsonUtil.parse (text), base_dir);
        }

        public Project load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            Project p;
            if (data.length > 0 && data[0] == '{') {
                var sb = new StringBuilder.sized (data.length + 1);
                sb.append_len ((string) data, data.length);
                p = project_from_json (JsonUtil.parse (sb.str), Path.get_dirname (path));
            } else {
                p = load_bytes (data, Path.get_dirname (path));
            }
            p.path = path;
            p.modified = false;
            return p;
        }

        public string snapshot (Project p) {
            return JsonUtil.to_string (project_to_json (p), false);
        }

        public Project restore (string snapshot, string base_dir) throws Error {
            return project_from_json (JsonUtil.parse (snapshot), base_dir);
        }
    }
}
