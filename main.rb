# encoding: UTF-8

require 'csv'

require './lib/environment.rb'
require './lib/trollop.rb'
require './lib/export_lib.rb'
require './lib/import_lib.rb'

opts = Trollop::options do
  opt :project_id, "Project ID", :type => Integer
  opt :import, "Import data from file", :type => String
  opt :export, "Export skeleton data"
end

def validate_arg_list(opts)
  Trollop::die :project_id, "If you are not importing a file, then you must supply a project id" unless opts[:project_id_given] || opts[:import_given]
end

def get_lof_efs(p_id)
  ExtractionForm.find(:all, :conditions => { :project_id => p_id })
end

def main(opts)
  validate_arg_list(opts)
  load_rails_environment

  if opts[:export]
    efs = get_lof_efs(p_id=opts[:project_id])
    efs.each do |ef|
      ex = Exporter.new(p_id=opts[:project_id], ef_id=ef.id, is_diagnostic=ef.is_diagnostic)
      ex.export
      ex.log_errors
    end

  elsif opts[:import]
    puts "import mode"
    puts opts[:import]
    im = Importer.new(file_path=opts[:import])
    im.import
  end
end




if __FILE__ == $0
  main(opts)
end
