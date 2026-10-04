require "./carbon/version"
require "./carbon/vcs"
require "./carbon/file_manager"
require "./carbon/hook_manager"
require "./carbon/changelog"
require "./carbon/badges"
require "./carbon/release_manager"
require "./carbon/doctor"
require "./carbon/dsl"

module Carbon
  # Carbon's own embedded version
  Carbon.version!
end
