project('singularity-keyframe', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-keyframe"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc         = meson.get_compiler('c')
gee_dep    = dependency('gee-0.8')
gio_dep    = dependency('gio-2.0')
json_dep   = dependency('json-glib-1.0')
zlib_dep   = dependency('zlib')
cairo_dep  = dependency('cairo')
pango_dep  = dependency('pangocairo')
pixbuf_dep = dependency('gdk-pixbuf-2.0')
gtk_dep    = dependency('gtk4')
math_dep   = cc.find_library('m')
gst_dep    = dependency('gstreamer-1.0')
gst_app_dep = dependency('gstreamer-app-1.0')
gst_base_dep = dependency('gstreamer-base-1.0')
gst_video_dep = dependency('gstreamer-video-1.0')
gst_pbutils_dep = dependency('gstreamer-pbutils-1.0')
peas_dep   = dependency('libpeas-2')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core_deps = [gee_dep, gio_dep, json_dep, zlib_dep, cairo_dep, pango_dep, pixbuf_dep, gtk_dep, math_dep,
             gst_dep, gst_app_dep, gst_base_dep, gst_video_dep, gst_pbutils_dep, libsingularity_dep]
core_args = ['--pkg', 'zlib']
core_inc = include_directories('src/render')

model = files(
  'src/core/math.vala',
  'src/core/bezpath.vala',
  'src/core/property.vala',
  'src/core/layer.vala',
  'src/core/project.vala',
  'src/core/factory.vala',
  'src/core/color.vala',
)

io = files(
  'src/io/zip.vala',
  'src/io/native.vala',
  'src/io/media.vala',
  'src/io/image_io.vala',
  'src/io/exr.vala',
  'src/io/tiff.vala',
  'src/io/encoder.vala',
  'src/io/render_job.vala',
  'src/io/lottie.vala',
  'src/io/otio.vala',
  'src/io/gif.vala',
  'src/io/audio_mix.vala',
  'src/io/templates.vala',
)

expr = files(
  'src/expr/interpreter.vala',
  'src/expr/expressions.vala',
  'src/expr/script.vala',
)

track = files(
  'src/track/point_tracker.vala',
  'src/track/planar.vala',
  'src/track/stabilizer.vala',
  'src/track/camera_solver.vala',
  'src/track/roto.vala',
)

render = files(
  'src/render/buffer.vala',
  'src/render/raster.vala',
  'src/render/blur.vala',
  'src/render/pathops.vala',
  'src/render/shapes.vala',
  'src/render/masks.vala',
  'src/render/text.vala',
  'src/render/text_offsets.vala',
  'src/render/effects.vala',
  'src/render/effects_basic.vala',
  'src/render/effects_color.vala',
  'src/render/effects_distort.vala',
  'src/render/effects_generate.vala',
  'src/render/effects_keying.vala',
  'src/render/effects_time.vala',
  'src/render/effects_controls.vala',
  'src/render/effects_advanced.vala',
  'src/render/model.vala',
  'src/render/puppet.vala',
  'src/render/particles.vala',
  'src/render/tokens.vala',
  'src/render/cache.vala',
  'src/render/renderer.vala',
  'src/render/cairo_path.c',
)

core = model + io + render + expr + track

core_lib = static_library('keyframe-core',
  core,
  dependencies: core_deps,
  vala_args: core_args,
  include_directories: core_inc,
  vala_header: 'keyframe-core.h',
  vala_vapi: 'keyframe-core.vapi',
)
core_dep = declare_dependency(
  link_with: core_lib,
  dependencies: core_deps,
  include_directories: [core_inc, include_directories('.')],
)
core_vala_args = core_args + ['--vapidir', meson.current_build_dir(), '--pkg', 'keyframe-core']

test_env = ['TMPDIR=' + meson.current_build_dir(), 'KEYFRAME_FIXTURES=' + meson.current_source_dir() / 'tests' / 'data', 'LC_ALL=C.UTF-8', 'GSK_RENDERER=cairo']

foreach t : ['model', 'render', 'expr', 'output', 'track', 'effects']
  exe = executable('keyframe-' + t + '-test',
    files('tests/harness.vala', 'tests/' + t.underscorify() + '_test.vala'),
    dependencies: [core_dep],
    vala_args: core_vala_args,
    link_depends: core_lib,
  )
  test('keyframe-' + t, exe, env: test_env, timeout: 600)
endforeach

subdir('src/cli')
subdir('src/plugin')

gnome = import('gnome')
resources = gnome.compile_resources('singularity-keyframe-resources',
  'data/dev.sinty.keyframe.gresource.xml',
  source_dir: meson.current_source_dir() / 'data',
)

ui = files(
  'src/ui/fixed_width.vala',
  'src/ui/document.vala',
  'src/ui/viewer.vala',
  'src/ui/timeline.vala',
  'src/ui/graph_editor.vala',
  'src/ui/prop_editor.vala',
  'src/ui/inspector.vala',
  'src/ui/project_panel.vala',
  'src/ui/dialogs.vala',
  'src/ui/exports.vala',
  'src/ui/integration.vala',
  'src/ui/render_queue.vala',
  'src/ui/vector_shapes.vala',
  'src/ui/library_panel.vala',
  'src/ui/test_script.vala',
  'src/ui/window.vala',
  'src/ui/app.vala',
)

draw = subproject('singularity-draw')
vector_engine_dep = draw.get_variable('vector_engine_dep')

executable('singularity-keyframe',
  ui + [resources] + effect_plugin_sources,
  dependencies: [core_dep, vector_engine_dep] + effect_plugin_deps,
  install_rpath: get_option('prefix') / get_option('libdir'),
  vala_args: core_vala_args,
  link_depends: core_lib,
  install: true,
)

vector_import_test = executable('keyframe-vector-import-test',
  files('src/ui/vector_shapes.vala', 'tests/harness.vala', 'tests/vector_import_test.vala'),
  dependencies: [core_dep, vector_engine_dep],
  vala_args: core_vala_args,
  link_depends: core_lib,
)
test('keyframe-vector-import', vector_import_test, env: test_env, timeout: 300)

install_data('data/dev.sinty.keyframe.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.keyframe.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.keyframe.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.keyframe.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
install_data('data/dev.sinty.keyframe.xml',
  install_dir: get_option('datadir') / 'mime' / 'packages'
)
install_data('data/dev.sinty.keyframe.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo'
)
install_data('data/icons/dev.sinty.keyframe.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
