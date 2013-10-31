def load_rails_environment
  ENV["RAILS_ENV"] = ARGV.first || ENV["RAILS_ENV"] || "development"
  require File.expand_path("~/Hive/Ruby/Rails/SRDR/config/environment")
  #require File.expand_path(File.dirname(__FILE__) + "./../../SRDR-dev/config/environment")
end
