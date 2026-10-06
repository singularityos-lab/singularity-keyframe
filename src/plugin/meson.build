effect_api = shared_library('keyframe-effect',
  files('effect_plugin.vala'),
  dependencies: [gio_dep],
  vala_header: 'keyframe-effect.h',
  vala_vapi: 'keyframe-effect.vapi',
  install: true,
  install_dir: [get_option('libdir'), true, true],
)
effect_api_dep = declare_dependency(link_with: effect_api, include_directories: include_directories('.'))
effect_plugin_sources = files('loader.vala')
effect_plugin_deps = [effect_api_dep, peas_dep]

chromatic_plugin = shared_module('keyframe-chromatic-aberration',
  files('sample/chromatic_aberration.vala'),
  dependencies: [gio_dep, peas_dep, effect_api_dep, math_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity-keyframe' / 'plugins' / 'chromatic-aberration',
)
configure_file(input: 'sample/chromatic-aberration.plugin', output: 'chromatic-aberration.plugin', copy: true)
install_data('sample/chromatic-aberration.plugin',
  install_dir: get_option('libdir') / 'singularity-keyframe' / 'plugins' / 'chromatic-aberration'
)

plugin_test = executable('keyframe-plugin-test',
  effect_plugin_sources + files('plugin_test.vala'),
  dependencies: [core_dep] + effect_plugin_deps,
  vala_args: core_vala_args,
  link_depends: core_lib,
)
test('keyframe-plugin', plugin_test, env: test_env + ['SINGULARITY_KEYFRAME_PLUGIN_PATH=' + meson.current_build_dir()], timeout: 300, depends: [chromatic_plugin])
