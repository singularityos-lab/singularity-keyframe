namespace Singularity.Apps.Keyframe {

    namespace TextOffsets {
        public unichar shift_char (unichar ch, int n) {
            if (n == 0) return ch;
            if (ch >= 'a' && ch <= 'z') return (unichar) ('a' + (((int) (ch - 'a') + n) % 26 + 26) % 26);
            if (ch >= 'A' && ch <= 'Z') return (unichar) ('A' + (((int) (ch - 'A') + n) % 26 + 26) % 26);
            if (ch >= '0' && ch <= '9') return (unichar) ('0' + (((int) (ch - '0') + n) % 10 + 10) % 10);
            return ch;
        }

        public TextDocument apply (PropGroup text, TextDocument doc, double t) {
            var animators = text.group ("animators");
            if (animators == null) return doc;
            var users = new Gee.ArrayList<PropGroup> ();
            foreach (var an in animators.groups_of_type ("text.animator")) {
                if (!an.enabled) continue;
                var props = an.group ("properties");
                if (props != null && props.prop ("character-offset") != null) users.add (an);
            }
            if (users.size == 0) return doc;
            var tl = TextRenderer.layout_glyphs (doc);
            int count = doc.text.char_count ();
            var offsets = new int[int.max (count, tl.char_count) + 1];
            var done = new Gee.HashSet<int> ();
            foreach (var an in users) {
                double val = an.group ("properties").prop ("character-offset").scalar_at (t);
                var sels = an.group ("selectors");
                done.clear ();
                foreach (var g in tl.glyphs) {
                    if (g.char_index < 0 || g.char_index >= offsets.length || done.contains (g.char_index)) continue;
                    done.add (g.char_index);
                    double amt = 1;
                    bool first = true;
                    if (sels != null) {
                        foreach (var c in sels.children) {
                            var sel = c as PropGroup;
                            if (sel == null || !sel.enabled) continue;
                            amt = TextRenderer.combine (amt, TextRenderer.selector_amount (sel, g, tl, t, text.owner_layer ()), sel.attr ("mode", "add"), first);
                            first = false;
                        }
                    }
                    offsets[g.char_index] += (int) Math.round (val * amt);
                }
            }
            var sb = new StringBuilder ();
            int idx = 0, i = 0;
            unichar ch;
            bool changed = false;
            while (doc.text.get_next_char (ref idx, out ch)) {
                var nc = i < offsets.length ? shift_char (ch, offsets[i]) : ch;
                if (nc != ch) changed = true;
                sb.append_unichar (nc);
                i++;
            }
            if (!changed) return doc;
            var r = doc.copy ();
            r.text = sb.str;
            return r;
        }
    }
}
