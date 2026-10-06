using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public errordomain ImageError {
        FORMAT,
        UNSUPPORTED
    }

    namespace ImageIO {
        public FloatImage load (string path, string color_space = "srgb") throws Error {
            var lower = path.down ();
            FloatImage img;
            if (lower.has_suffix (".exr")) {
                uint8[] data;
                FileUtils.get_data (path, out data);
                img = Exr.decode (data);
                if (color_space != "srgb" && color_space != "linear") ColorManagement.to_working (img, color_space, "linear-srgb");
                return img;
            }
            if (lower.has_suffix (".tif") || lower.has_suffix (".tiff")) {
                uint8[] data;
                FileUtils.get_data (path, out data);
                try {
                    img = Tiff.decode (data);
                    if (color_space == "srgb" && !Tiff.last_was_float) linearize (img);
                    else if (color_space != "linear" && color_space != "srgb") ColorManagement.to_working (img, color_space, "linear-srgb");
                    return img;
                } catch (Error e) {
                }
            }
            var texture = Gdk.Texture.from_filename (path);
            img = FloatImage.from_texture (texture, color_space == "srgb");
            if (color_space != "srgb" && color_space != "linear") ColorManagement.to_working (img, color_space, "linear-srgb");
            return img;
        }

        public void linearize (FloatImage img) {
            size_t n = img.pixel_count ();
            for (size_t i = 0; i < n; i++)
                for (int c = 0; c < 3; c++) img.data[i * 4 + c] = Transfer.srgb_to_linear (img.data[i * 4 + c]);
        }

        private void put32be (ByteArray b, uint32 v) {
            uint8[] x = { (uint8) (v >> 24), (uint8) (v >> 16), (uint8) (v >> 8), (uint8) v };
            b.append (x);
        }

        private void png_chunk (ByteArray out_data, string type, uint8[] payload) {
            put32be (out_data, payload.length);
            var tb = new ByteArray ();
            tb.append (type.data);
            tb.append (payload);
            out_data.append (tb.data);
            put32be (out_data, (uint32) ZLib.Utility.crc32 (0, tb.data));
        }

        public uint8[] deflate_zlib (uint8[] raw, int level = 6) throws Error {
            var conv = new ZlibCompressor (ZlibCompressorFormat.ZLIB, level);
            var mem = new MemoryOutputStream.resizable ();
            var stream = new ConverterOutputStream (mem, conv);
            size_t written;
            stream.write_all (raw, out written);
            stream.close ();
            var r = mem.steal_data ();
            r.length = (int) mem.get_data_size ();
            return r;
        }

        public uint8[] inflate_zlib (uint8[] data, size_t expected = 0) throws Error {
            var conv = new ZlibDecompressor (ZlibCompressorFormat.ZLIB);
            var stream = new ConverterInputStream (new MemoryInputStream.from_data (data), conv);
            var out_buf = new ByteArray.sized ((uint) (expected > 0 ? expected : 65536));
            uint8[] chunk = new uint8[65536];
            ssize_t n;
            while ((n = stream.read (chunk)) > 0) out_buf.append (chunk[0:n]);
            return out_buf.steal ();
        }

        public uint8[] encode_png (FloatImage premul, int bit_depth, bool alpha, bool encode_srgb = true) throws Error {
            var img = Pixels.unpremultiplied (premul);
            int w = img.width, h = img.height;
            int channels = alpha ? 4 : 3;
            int bps = bit_depth >= 16 ? 2 : 1;
            int row = 1 + w * channels * bps;
            var raw = new uint8[(size_t) row * h];
            for (int y = 0; y < h; y++) {
                raw[(size_t) y * row] = 0;
                for (int x = 0; x < w; x++) {
                    size_t i = img.offset (x, y);
                    for (int c = 0; c < channels; c++) {
                        float v = img.data[i + c];
                        if (c < 3 && encode_srgb) v = Transfer.linear_to_srgb (v.clamp (0, 1));
                        v = v.clamp (0, 1);
                        size_t o = (size_t) y * row + 1 + ((size_t) x * channels + c) * bps;
                        if (bps == 2) {
                            uint16 s = (uint16) Math.roundf (v * 65535);
                            raw[o] = (uint8) (s >> 8);
                            raw[o + 1] = (uint8) (s & 0xff);
                        } else {
                            raw[o] = (uint8) Math.roundf (v * 255);
                        }
                    }
                }
            }
            var out_data = new ByteArray ();
            uint8[] sig = { 137, 80, 78, 71, 13, 10, 26, 10 };
            out_data.append (sig);
            var ihdr = new ByteArray ();
            put32be (ihdr, w);
            put32be (ihdr, h);
            uint8[] rest = { (uint8) (bps * 8), (uint8) (alpha ? 6 : 2), 0, 0, 0 };
            ihdr.append (rest);
            png_chunk (out_data, "IHDR", ihdr.data);
            if (encode_srgb) png_chunk (out_data, "sRGB", { 0 });
            png_chunk (out_data, "IDAT", deflate_zlib (raw));
            png_chunk (out_data, "IEND", {});
            return out_data.steal ();
        }

        public void save_png (FloatImage premul, string path, int bit_depth = 8, bool alpha = true) throws Error {
            FileUtils.set_data (path, encode_png (premul, bit_depth, alpha));
        }

        public void save_pixbuf (FloatImage premul, string path, string type, int quality, bool alpha) throws Error {
            var img = Pixels.unpremultiplied (premul);
            var px = img.to_rgba8 (true);
            var pb = new Gdk.Pixbuf.from_data (px, Gdk.Colorspace.RGB, true, 8, img.width, img.height, img.width * 4);
            if (!alpha) {
                var flat = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, img.width, img.height);
                flat.fill (0x000000ff);
                pb.composite (flat, 0, 0, img.width, img.height, 0, 0, 1, 1, Gdk.InterpType.NEAREST, 255);
                pb = flat;
            }
            if (type == "jpeg") pb.savev (path, "jpeg", { "quality" }, { quality.clamp (1, 100).to_string () });
            else if (type == "webp") pb.savev (path, "webp", { "quality" }, { quality.clamp (1, 100).to_string () });
            else pb.savev (path, type, {}, {});
        }

        public bool pixbuf_can_save (string type) {
            foreach (var f in Gdk.Pixbuf.get_formats ()) if (f.get_name () == type && f.is_writable ()) return true;
            return false;
        }
    }
}
