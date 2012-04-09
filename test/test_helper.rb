require File.expand_path('../../lib/boot', __FILE__)
Bundler.require(:default, :test)
require 'ci/reporter/rake/test_unit_loader'
$worker_id = 0
require File.expand_path('../../config/defaults.rb', __FILE__)
require File.expand_path('../../config/test.rb', __FILE__)
