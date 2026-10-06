#define PACKAGE "singularity-keyframe"
#include <string.h>
#include <gst/gst.h>
#include <gst/base/gstadapter.h>
#include "keyframe-gst.h"

#define KEYFRAME_MIME "application/x-keyframe"

typedef struct _GstKeyframeDec {
  GstElement parent;
  GstPad *sinkpad;
  GstPad *srcpad;
  GstAdapter *adapter;
  SingularityAppsKeyframeGstStream *stream;
  gboolean loaded;
  gboolean pull_mode;
  gboolean need_start;
  gboolean need_segment;
  gint64 frame;
  GstSegment segment;
  guint32 seqnum;
  gchar *composition;
  gchar *overrides;
} GstKeyframeDec;

typedef struct _GstKeyframeDecClass {
  GstElementClass parent_class;
} GstKeyframeDecClass;

enum {
  PROP_0,
  PROP_COMPOSITION,
  PROP_OVERRIDES
};

GType gst_keyframe_dec_get_type (void);
G_DEFINE_TYPE (GstKeyframeDec, gst_keyframe_dec, GST_TYPE_ELEMENT)

static GstStaticPadTemplate sink_template = GST_STATIC_PAD_TEMPLATE ("sink", GST_PAD_SINK, GST_PAD_ALWAYS, GST_STATIC_CAPS (KEYFRAME_MIME));
static GstStaticPadTemplate src_template = GST_STATIC_PAD_TEMPLATE ("src", GST_PAD_SRC, GST_PAD_ALWAYS,
    GST_STATIC_CAPS ("video/x-raw, format=(string)RGBA, width=(int)[1,32768], height=(int)[1,32768], framerate=(fraction)[0/1,1000/1]"));

static GstClockTime
frame_time (GstKeyframeDec *self, gint64 frame)
{
  if (self->stream == NULL || self->stream->fps_n <= 0)
    return 0;
  return gst_util_uint64_scale (frame, GST_SECOND * (guint64) self->stream->fps_d, self->stream->fps_n);
}

static gchar *
upstream_dir (GstKeyframeDec *self)
{
  GstQuery *q = gst_query_new_uri ();
  gchar *dir = NULL;
  if (gst_pad_peer_query (self->sinkpad, q)) {
    gchar *uri = NULL;
    gst_query_parse_uri (q, &uri);
    if (uri != NULL) {
      gchar *path = g_filename_from_uri (uri, NULL, NULL);
      if (path != NULL) {
        dir = g_path_get_dirname (path);
        g_free (path);
      }
      g_free (uri);
    }
  }
  gst_query_unref (q);
  return dir;
}

static gboolean
load_bytes (GstKeyframeDec *self, const guint8 *data, gsize size)
{
  gchar *dir = upstream_dir (self);
  if (self->stream != NULL)
    g_object_unref (self->stream);
  self->stream = singularity_apps_keyframe_gst_stream_new ();
  gboolean ok = singularity_apps_keyframe_gst_stream_load (self->stream, (guint8 *) data, (gint) size, self->composition, self->overrides, dir);
  g_free (dir);
  if (!ok) {
    GST_ELEMENT_ERROR (self, STREAM, DECODE, ("%s", self->stream->error), (NULL));
    return FALSE;
  }
  self->loaded = TRUE;
  return TRUE;
}

static gboolean
load_pull (GstKeyframeDec *self)
{
  gint64 size = 0;
  if (!gst_pad_peer_query_duration (self->sinkpad, GST_FORMAT_BYTES, &size) || size <= 0) {
    GST_ELEMENT_ERROR (self, STREAM, DECODE, ("Cannot read the project size"), (NULL));
    return FALSE;
  }
  GstBuffer *buf = NULL;
  if (gst_pad_pull_range (self->sinkpad, 0, (guint) size, &buf) != GST_FLOW_OK || buf == NULL) {
    GST_ELEMENT_ERROR (self, STREAM, DECODE, ("Cannot read the project"), (NULL));
    return FALSE;
  }
  GstMapInfo map;
  gboolean ok = FALSE;
  if (gst_buffer_map (buf, &map, GST_MAP_READ)) {
    ok = load_bytes (self, map.data, map.size);
    gst_buffer_unmap (buf, &map);
  }
  gst_buffer_unref (buf);
  return ok;
}

static void
push_start (GstKeyframeDec *self)
{
  gchar *sid = gst_pad_create_stream_id (self->srcpad, GST_ELEMENT (self), "keyframe");
  gst_pad_push_event (self->srcpad, gst_event_new_stream_start (sid));
  g_free (sid);
  GstCaps *caps = gst_caps_new_simple ("video/x-raw",
      "format", G_TYPE_STRING, "RGBA",
      "width", G_TYPE_INT, self->stream->width,
      "height", G_TYPE_INT, self->stream->height,
      "framerate", GST_TYPE_FRACTION, self->stream->fps_n, self->stream->fps_d,
      "pixel-aspect-ratio", GST_TYPE_FRACTION, 1, 1,
      "colorimetry", G_TYPE_STRING, "sRGB",
      NULL);
  gst_pad_push_event (self->srcpad, gst_event_new_caps (caps));
  gst_caps_unref (caps);
}

static void
loop (gpointer data)
{
  GstKeyframeDec *self = data;
  if (!self->loaded) {
    gboolean ok = FALSE;
    if (self->pull_mode)
      ok = load_pull (self);
    if (!ok) {
      gst_pad_push_event (self->srcpad, gst_event_new_eos ());
      gst_pad_pause_task (self->srcpad);
      return;
    }
    self->segment.duration = self->stream->duration_ns;
  }
  if (self->need_start) {
    push_start (self);
    self->need_start = FALSE;
  }
  if (self->need_segment) {
    self->segment.duration = self->stream->duration_ns;
    if (self->segment.stop == GST_CLOCK_TIME_NONE || self->segment.stop > (guint64) self->stream->duration_ns)
      self->segment.stop = self->stream->duration_ns;
    GstEvent *ev = gst_event_new_segment (&self->segment);
    if (self->seqnum != 0)
      gst_event_set_seqnum (ev, self->seqnum);
    gst_pad_push_event (self->srcpad, ev);
    self->need_segment = FALSE;
  }
  GstClockTime pts = frame_time (self, self->frame);
  if (self->frame >= self->stream->frame_count || (self->segment.stop != GST_CLOCK_TIME_NONE && pts >= self->segment.stop)) {
    GstEvent *eos = gst_event_new_eos ();
    if (self->seqnum != 0)
      gst_event_set_seqnum (eos, self->seqnum);
    gst_pad_push_event (self->srcpad, eos);
    gst_pad_pause_task (self->srcpad);
    return;
  }
  gint len = 0;
  guint8 *pixels = singularity_apps_keyframe_gst_stream_render_frame (self->stream, (gint) self->frame, &len);
  GstBuffer *buf = gst_buffer_new_wrapped (pixels, len);
  GST_BUFFER_PTS (buf) = pts;
  GST_BUFFER_DTS (buf) = pts;
  GST_BUFFER_DURATION (buf) = frame_time (self, self->frame + 1) - pts;
  self->frame++;
  self->segment.position = pts;
  GstFlowReturn ret = gst_pad_push (self->srcpad, buf);
  if (ret != GST_FLOW_OK) {
    if (ret == GST_FLOW_EOS) {
      gst_pad_push_event (self->srcpad, gst_event_new_eos ());
    } else if (ret < GST_FLOW_EOS || ret == GST_FLOW_NOT_LINKED) {
      GST_ELEMENT_FLOW_ERROR (self, ret);
      gst_pad_push_event (self->srcpad, gst_event_new_eos ());
    }
    gst_pad_pause_task (self->srcpad);
  }
}

static gboolean
handle_seek (GstKeyframeDec *self, GstEvent *event)
{
  gdouble rate;
  GstFormat format;
  GstSeekFlags flags;
  GstSeekType start_type, stop_type;
  gint64 start, stop;
  gst_event_parse_seek (event, &rate, &format, &flags, &start_type, &start, &stop_type, &stop);
  if (format != GST_FORMAT_TIME || rate <= 0)
    return FALSE;
  gboolean flush = (flags & GST_SEEK_FLAG_FLUSH) != 0;
  guint32 seqnum = gst_event_get_seqnum (event);
  if (flush) {
    GstEvent *fs = gst_event_new_flush_start ();
    gst_event_set_seqnum (fs, seqnum);
    gst_pad_push_event (self->srcpad, fs);
  } else {
    gst_pad_pause_task (self->srcpad);
  }
  GST_PAD_STREAM_LOCK (self->srcpad);
  gboolean update;
  gst_segment_do_seek (&self->segment, rate, format, flags, start_type, start, stop_type, stop, &update);
  if (self->stream != NULL && self->stream->fps_d > 0)
    self->frame = gst_util_uint64_scale (self->segment.position, self->stream->fps_n, GST_SECOND * (guint64) self->stream->fps_d);
  else
    self->frame = 0;
  self->seqnum = seqnum;
  if (flush) {
    GstEvent *fe = gst_event_new_flush_stop (TRUE);
    gst_event_set_seqnum (fe, seqnum);
    gst_pad_push_event (self->srcpad, fe);
  }
  self->need_segment = TRUE;
  if (self->loaded || self->pull_mode)
    gst_pad_start_task (self->srcpad, loop, self, NULL);
  GST_PAD_STREAM_UNLOCK (self->srcpad);
  return TRUE;
}

static gboolean
src_event (GstPad *pad, GstObject *parent, GstEvent *event)
{
  GstKeyframeDec *self = (GstKeyframeDec *) parent;
  if (GST_EVENT_TYPE (event) == GST_EVENT_SEEK) {
    gboolean res = handle_seek (self, event);
    gst_event_unref (event);
    return res;
  }
  return gst_pad_event_default (pad, parent, event);
}

static gboolean
src_query (GstPad *pad, GstObject *parent, GstQuery *query)
{
  GstKeyframeDec *self = (GstKeyframeDec *) parent;
  switch (GST_QUERY_TYPE (query)) {
    case GST_QUERY_DURATION: {
      GstFormat fmt;
      gst_query_parse_duration (query, &fmt, NULL);
      if (fmt != GST_FORMAT_TIME || !self->loaded)
        return FALSE;
      gst_query_set_duration (query, GST_FORMAT_TIME, self->stream->duration_ns);
      return TRUE;
    }
    case GST_QUERY_POSITION: {
      GstFormat fmt;
      gst_query_parse_position (query, &fmt, NULL);
      if (fmt != GST_FORMAT_TIME)
        return FALSE;
      gst_query_set_position (query, GST_FORMAT_TIME, self->segment.position);
      return TRUE;
    }
    case GST_QUERY_SEEKING: {
      GstFormat fmt;
      gst_query_parse_seeking (query, &fmt, NULL, NULL, NULL);
      if (fmt != GST_FORMAT_TIME)
        return FALSE;
      gst_query_set_seeking (query, GST_FORMAT_TIME, TRUE, 0, self->loaded ? self->stream->duration_ns : -1);
      return TRUE;
    }
    default:
      return gst_pad_query_default (pad, parent, query);
  }
}

static GstFlowReturn
sink_chain (GstPad *pad, GstObject *parent, GstBuffer *buf)
{
  GstKeyframeDec *self = (GstKeyframeDec *) parent;
  gst_adapter_push (self->adapter, buf);
  return GST_FLOW_OK;
}

static gboolean
sink_event (GstPad *pad, GstObject *parent, GstEvent *event)
{
  GstKeyframeDec *self = (GstKeyframeDec *) parent;
  switch (GST_EVENT_TYPE (event)) {
    case GST_EVENT_EOS: {
      gsize size = gst_adapter_available (self->adapter);
      gboolean ok = FALSE;
      if (size > 0 && !self->loaded) {
        guint8 *d = gst_adapter_take (self->adapter, size);
        ok = load_bytes (self, d, size);
        g_free (d);
      }
      gst_event_unref (event);
      if (ok) {
        self->segment.duration = self->stream->duration_ns;
        gst_pad_start_task (self->srcpad, loop, self, NULL);
      } else {
        gst_pad_push_event (self->srcpad, gst_event_new_eos ());
      }
      return TRUE;
    }
    case GST_EVENT_STREAM_START:
    case GST_EVENT_CAPS:
    case GST_EVENT_SEGMENT:
      gst_event_unref (event);
      return TRUE;
    default:
      return gst_pad_event_default (pad, parent, event);
  }
}

static gboolean
sink_activate (GstPad *pad, GstObject *parent)
{
  GstQuery *q = gst_query_new_scheduling ();
  gboolean pull = FALSE;
  if (gst_pad_peer_query (pad, q))
    pull = gst_query_has_scheduling_mode_with_flags (q, GST_PAD_MODE_PULL, GST_SCHEDULING_FLAG_SEEKABLE);
  gst_query_unref (q);
  if (pull)
    return gst_pad_activate_mode (pad, GST_PAD_MODE_PULL, TRUE);
  return gst_pad_activate_mode (pad, GST_PAD_MODE_PUSH, TRUE);
}

static gboolean
sink_activate_mode (GstPad *pad, GstObject *parent, GstPadMode mode, gboolean active)
{
  GstKeyframeDec *self = (GstKeyframeDec *) parent;
  if (mode == GST_PAD_MODE_PULL) {
    self->pull_mode = active;
    if (active)
      return gst_pad_start_task (self->srcpad, loop, self, NULL);
    return gst_pad_stop_task (self->srcpad);
  }
  if (mode == GST_PAD_MODE_PUSH) {
    self->pull_mode = FALSE;
    if (!active)
      gst_pad_stop_task (self->srcpad);
    return TRUE;
  }
  return FALSE;
}

static GstStateChangeReturn
change_state (GstElement *element, GstStateChange transition)
{
  GstKeyframeDec *self = (GstKeyframeDec *) element;
  if (transition == GST_STATE_CHANGE_READY_TO_PAUSED) {
    gst_segment_init (&self->segment, GST_FORMAT_TIME);
    self->frame = 0;
    self->need_start = TRUE;
    self->need_segment = TRUE;
    self->seqnum = 0;
    gst_adapter_clear (self->adapter);
  }
  GstStateChangeReturn ret = GST_ELEMENT_CLASS (gst_keyframe_dec_parent_class)->change_state (element, transition);
  if (transition == GST_STATE_CHANGE_PAUSED_TO_READY) {
    self->loaded = FALSE;
    g_clear_object (&self->stream);
    gst_adapter_clear (self->adapter);
  }
  return ret;
}

static void
set_property (GObject *object, guint id, const GValue *value, GParamSpec *pspec)
{
  GstKeyframeDec *self = (GstKeyframeDec *) object;
  switch (id) {
    case PROP_COMPOSITION:
      g_free (self->composition);
      self->composition = g_value_dup_string (value);
      break;
    case PROP_OVERRIDES:
      g_free (self->overrides);
      self->overrides = g_value_dup_string (value);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, id, pspec);
  }
}

static void
get_property (GObject *object, guint id, GValue *value, GParamSpec *pspec)
{
  GstKeyframeDec *self = (GstKeyframeDec *) object;
  switch (id) {
    case PROP_COMPOSITION:
      g_value_set_string (value, self->composition);
      break;
    case PROP_OVERRIDES:
      g_value_set_string (value, self->overrides);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, id, pspec);
  }
}

static void
finalize (GObject *object)
{
  GstKeyframeDec *self = (GstKeyframeDec *) object;
  g_clear_object (&self->stream);
  g_clear_object (&self->adapter);
  g_free (self->composition);
  g_free (self->overrides);
  G_OBJECT_CLASS (gst_keyframe_dec_parent_class)->finalize (object);
}

static void
gst_keyframe_dec_class_init (GstKeyframeDecClass *klass)
{
  GObjectClass *gobject_class = G_OBJECT_CLASS (klass);
  GstElementClass *element_class = GST_ELEMENT_CLASS (klass);
  gobject_class->set_property = set_property;
  gobject_class->get_property = get_property;
  gobject_class->finalize = finalize;
  element_class->change_state = change_state;
  g_object_class_install_property (gobject_class, PROP_COMPOSITION,
      g_param_spec_string ("composition", "Composition", "Name or id of the composition to play; empty plays the main one", NULL, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property (gobject_class, PROP_OVERRIDES,
      g_param_spec_string ("overrides", "Overrides", "JSON object with Essential Graphics values by label", NULL, G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  gst_element_class_set_static_metadata (element_class, "Keyframe composition decoder", "Codec/Decoder/Video",
      "Renders a Keyframe composition as raw video on demand", "Singularity Desktop");
  gst_element_class_add_static_pad_template (element_class, &sink_template);
  gst_element_class_add_static_pad_template (element_class, &src_template);
}

static void
gst_keyframe_dec_init (GstKeyframeDec *self)
{
  self->sinkpad = gst_pad_new_from_static_template (&sink_template, "sink");
  gst_pad_set_activate_function (self->sinkpad, sink_activate);
  gst_pad_set_activatemode_function (self->sinkpad, sink_activate_mode);
  gst_pad_set_chain_function (self->sinkpad, sink_chain);
  gst_pad_set_event_function (self->sinkpad, sink_event);
  gst_element_add_pad (GST_ELEMENT (self), self->sinkpad);
  self->srcpad = gst_pad_new_from_static_template (&src_template, "src");
  gst_pad_set_event_function (self->srcpad, src_event);
  gst_pad_set_query_function (self->srcpad, src_query);
  gst_pad_use_fixed_caps (self->srcpad);
  gst_element_add_pad (GST_ELEMENT (self), self->srcpad);
  self->adapter = gst_adapter_new ();
  gst_segment_init (&self->segment, GST_FORMAT_TIME);
}

static void
typefind (GstTypeFind *tf, gpointer data)
{
  const guint8 *head = gst_type_find_peek (tf, 0, 60);
  if (head == NULL)
    return;
  if (memcmp (head, "PK\003\004", 4) != 0 || memcmp (head + 30, "mimetype", 8) != 0)
    return;
  if (memcmp (head + 38, KEYFRAME_MIME, strlen (KEYFRAME_MIME)) != 0)
    return;
  gst_type_find_suggest_empty_simple (tf, GST_TYPE_FIND_MAXIMUM, KEYFRAME_MIME);
}

static gboolean
plugin_init (GstPlugin *plugin)
{
  GstCaps *caps = gst_caps_new_empty_simple (KEYFRAME_MIME);
  gboolean ok = gst_type_find_register (plugin, "keyframe-project", GST_RANK_PRIMARY, typefind, "keyframe", caps, NULL, NULL);
  gst_caps_unref (caps);
  ok = ok && gst_element_register (plugin, "keyframedec", GST_RANK_PRIMARY, gst_keyframe_dec_get_type ());
  return ok;
}

GST_PLUGIN_DEFINE (GST_VERSION_MAJOR, GST_VERSION_MINOR, keyframe, "Keyframe compositions as live video",
    plugin_init, "0.1.0", "GPL", "singularity-keyframe", "https://github.com/singularityos-lab/singularity-desktop")
