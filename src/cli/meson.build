render_cli = executable('singularity-keyframe-render',
  files('main.vala'),
  dependencies: [core_dep],
  vala_args: core_vala_args,
  link_depends: core_lib,
  install: true,
)

subdir('gst')
